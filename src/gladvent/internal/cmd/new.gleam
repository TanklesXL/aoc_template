import envoy
import filepath
import gladvent/internal/cmd
import gladvent/internal/input
import gladvent/internal/parse.{type Day}
import gladvent/internal/util
import gleam/bool
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import glint
import simplifile

const aoc_cookie_name = "AOC_COOKIE"

type Context {
  Context(
    year: Int,
    day: Day,
    add_parse: Bool,
    create_example_file: Bool,
    fetch_input: Bool,
  )
}

fn create_src_file(ctx: Context) -> fn() -> Result(Success, Err) {
  fn() {
    let gleam_src_path = gleam_src_path(ctx.year, ctx.day)

    use _ <- result.try(
      simplifile.create_file(gleam_src_path)
      |> result.map_error(FailedToCreateFile(gleam_src_path, _)),
    )

    let file_data = case ctx.add_parse {
      True -> parse_starter <> "\n" <> gleam_starter
      False -> gleam_starter
    }

    simplifile.write(gleam_src_path, file_data)
    |> result.map_error(FailedToWriteToFile(gleam_src_path, _))
    |> result.replace(File(gleam_src_path))
  }
}

fn create_input_file(
  ctx: Context,
  kind: input.Kind,
) -> fn() -> Result(Success, Err) {
  fn() {
    let input_path = input.get_file_path(ctx.year, ctx.day, kind)
    use Nil <- result.try(
      simplifile.create_file(input_path)
      |> result.map_error(FailedToCreateFile(input_path, _)),
    )
    use <- bool.guard(
      when: kind == input.Example || !ctx.fetch_input,
      return: Ok(File(input_path)),
    )
    use content <- result.try(download_input(ctx))
    simplifile.write(input_path, content)
    |> result.map_error(FailedToWriteToFile(input_path, _))
    |> result.replace(File(input_path))
  }
}

type Success {
  Dir(String)
  File(String)
}

type Err {
  CookieNotDefined
  FailedToCreateDir(String, simplifile.FileError)
  FailedToCreateFile(String, simplifile.FileError)
  FailedToWriteToFile(String, simplifile.FileError)
  HttpError(httpc.HttpError)
  UnexpectedHttpResponse(response.Response(String))
}

fn err_to_string(e: Err) -> String {
  case e {
    CookieNotDefined ->
      "'" <> aoc_cookie_name <> "' environment variable not defined"
    FailedToCreateDir(d, e) ->
      "failed to create dir '" <> d <> "': " <> simplifile.describe_error(e)
    FailedToCreateFile(f, e) ->
      "failed to create file '" <> f <> "': " <> simplifile.describe_error(e)
    FailedToWriteToFile(f, e) ->
      "failed to write to file '" <> f <> "': " <> simplifile.describe_error(e)
    HttpError(e) ->
      "HTTP error while fetching input file: " <> string.inspect(e)
    UnexpectedHttpResponse(r) ->
      "unexpected HTTP response ("
      <> int.to_string(r.status)
      <> ") while fetching input file: "
      <> r.body
  }
}

fn gleam_src_path(year: Int, day: Day) -> String {
  filepath.join(cmd.src_dir(year), "day_" <> int.to_string(day) <> ".gleam")
}

fn create_dir(dir: String) -> fn() -> Result(Success, Err) {
  fn() {
    simplifile.create_directory_all(dir)
    |> handle_dir_open_res(dir)
    |> result.map(Dir)
  }
}

fn handle_dir_open_res(
  res: Result(_, simplifile.FileError),
  filename: String,
) -> Result(String, Err) {
  case res {
    Ok(_) -> Ok(filename)
    Error(simplifile.Eexist) -> Ok("")
    Error(e) -> Error(FailedToCreateDir(filename, e))
  }
}

fn get_cookie_value() -> Result(String, Err) {
  aoc_cookie_name
  |> envoy.get()
  |> result.replace_error(CookieNotDefined)
}

fn download_input(ctx: Context) -> Result(String, Err) {
  use cookie <- result.try(get_cookie_value())
  use resp <- result.try(
    request.new()
    |> request.set_host("adventofcode.com")
    |> request.set_path(
      "/"
      <> int.to_string(ctx.year)
      <> "/day/"
      <> int.to_string(ctx.day)
      <> "/input",
    )
    |> request.set_scheme(http.Https)
    |> request.set_cookie("session", cookie)
    |> request.set_header("user-agent", "github.com/TanklesXL/gladvent")
    |> httpc.send()
    |> result.map_error(HttpError),
  )
  case resp.status {
    200 -> Ok(resp.body)
    _ -> Error(UnexpectedHttpResponse(resp))
  }
}

fn do(ctx: Context) -> String {
  let seq = [
    create_dir(input.dir(ctx.year)),
    create_input_file(ctx, input.Puzzle),
    create_dir(cmd.src_dir(ctx.year)),
    create_src_file(ctx),
    ..case ctx.create_example_file {
      True -> [create_input_file(ctx, input.Example)]
      False -> []
    }
  ]

  let successes = fn(good) {
    case good {
      "" -> ""
      _ -> "created:" <> good
    }
  }

  let errors = fn(errs) {
    case errs {
      "" -> ""
      _ -> "errors:" <> errs
    }
  }

  let newline_tab = fn(a, b) { a <> "\n\t" <> b }

  let #(good, bad) =
    {
      use acc, f <- list.fold(seq, #("", ""))
      case f() {
        Ok(Dir(_)) -> acc
        Ok(File(o)) -> pair.map_first(acc, newline_tab(_, o))
        Error(err) -> pair.map_second(acc, newline_tab(_, err_to_string(err)))
      }
    }
    |> pair.map_first(successes)
    |> pair.map_second(errors)

  [good, bad]
  |> list.filter(fn(s) { s != "" })
  |> string.join("\n\n")
}

const gleam_starter = "pub fn pt_1(input: String) {
  todo as \"part 1 not implemented\"
}

pub fn pt_2(input: String) {
  todo as \"part 2 not implemented\"
}
"

const parse_starter = "pub fn parse(input: String) -> String {
  todo as \"parse not implemented\"
}
"

fn collect_async(year: Int, x: #(Day, Result(String, String))) -> String {
  fn(res) {
    case res {
      Ok(res) -> res
      Error(err) -> err
    }
  }
  |> pair.map_second(x, _)
  |> collect(year, _)
}

fn collect(year: Int, x: #(Day, String)) -> String {
  let day = int.to_string(x.0)
  let year = int.to_string(year)

  "initialized " <> year <> " day " <> day <> "\n" <> x.1
}

pub fn new_command() {
  use <- glint.command_help("Create .gleam and input files")
  use <- glint.unnamed_args(glint.MinArgs(1))
  use parse_flag <- glint.flag(
    glint.bool_flag("parse")
    |> glint.flag_default(False)
    |> glint.flag_help("Generate day runners with a parse function"),
  )
  use example_flag <- glint.flag(
    glint.bool_flag("example")
    |> glint.flag_default(False)
    |> glint.flag_help(
      "Generate example input files to run your solution against",
    ),
  )
  use fetch_flag <- glint.flag(
    glint.bool_flag("fetch")
    |> glint.flag_default(False)
    |> glint.flag_help("Fetch your own input from the AoC website.

    Needs to have your AoC cookie stored in the '" <> aoc_cookie_name <> "' environment variable"),
  )
  use _, args, flags <- glint.command()
  use days <- result.map(parse.days(args))
  let days = util.deduplicate_sort(days)
  let assert Ok(year) = glint.get_flag(flags, cmd.year_flag())
  let assert Ok(add_parse) = parse_flag(flags)
  let assert Ok(create_example_file) = example_flag(flags)
  let assert Ok(fetch_input) = fetch_flag(flags)

  cmd.exec(
    days,
    cmd.Endless,
    fn(day) {
      do(Context(year:, day:, add_parse:, create_example_file:, fetch_input:))
    },
    collect_async(year, _),
  )
}
