import gleam/map.{Map}
import gleam/string
import gleam/result
import gleam/int
import snag.{Result, Snag}

pub type FlagValue {
  BoolFlag(value: Bool)
  IntFlag(value: Int)
  StringFlag(value: String)
}

pub type Flag {
  Flag(name: String, value: FlagValue)
}

pub fn int(called name: String, default value: Int) -> Flag {
  Flag(name, IntFlag(value))
}

pub fn string(called name: String, default value: String) -> Flag {
  Flag(name, StringFlag(value))
}

pub fn bool(called name: String, default value: Bool) -> Flag {
  Flag(name, BoolFlag(value))
}

pub type FlagMap =
  Map(String, FlagValue)

pub fn update_flags(flags: FlagMap, flag_input: String) -> Result(FlagMap) {
  try #(key, value) =
    flag_input
    |> string.split_once("=")
    |> result.replace_error(no_value_flag_err(flag_input))

  try default =
    map.get(flags, key)
    |> result.replace_error(undefined_flag_err(key))

  try new_value = case default {
    IntFlag(_) ->
      value
      |> int.parse()
      |> result.replace_error(int_flag_err(key, value))
      |> result.map(IntFlag)
    StringFlag(_) -> Ok(StringFlag(value))

    BoolFlag(_) ->
      case value {
        "true" -> Ok(BoolFlag(True))
        "false" -> Ok(BoolFlag(False))
        _ -> Error(bool_flag_err(key, value))
      }
  }

  Ok(map.insert(flags, key, new_value))
}

fn layer_invalid_flag(err: Snag, flag: String) -> Snag {
  ["invalid flag '", flag, "'"]
  |> string.concat()
  |> snag.layer(err, _)
}

fn no_value_flag_err(flag_input: String) -> Snag {
  ["flag '", flag_input, "' has no assigned value"]
  |> string.concat()
  |> snag.new()
  |> layer_invalid_flag(flag_input)
}

fn undefined_flag_err(key: String) -> Snag {
  "flag provided but not defined"
  |> snag.new()
  |> layer_invalid_flag(key)
}

fn int_flag_err(key: String, value: String) -> Snag {
  ["cannot parse flag '", key, "' value '", value, "' as int"]
  |> string.concat()
  |> snag.new()
  |> layer_invalid_flag(key)
}

fn bool_flag_err(key: String, value: String) -> Snag {
  ["cannot parse flag '", key, "' value '", value, "' as boolean"]
  |> string.concat()
  |> snag.new()
  |> layer_invalid_flag(key)
}
