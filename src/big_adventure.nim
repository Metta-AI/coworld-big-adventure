import std/[json, os]
import bitworld/runtime
import jsony
import big_adventure/server

type
  BigAdventureError = object of CatchableError

  RunConfig = object
    address: string
    port: int
    seed: int
    maxTicks: int
    maxGames: int
    tokens: seq[string]
    profileTracePath: string
    profileTicks: int

proc readConfigStrings(node: JsonNode, name: string, values: var seq[string]) =
  ## Reads one optional string-array config field.
  if not node.hasKey(name):
    return
  let items = node[name]
  if items.kind != JArray:
    raise newException(
      BigAdventureError,
      "Config field " & name & " must be an array."
    )
  values.setLen(0)
  for i in 0 ..< items.len:
    let item = items[i]
    if item.kind != JString:
      raise newException(
        BigAdventureError,
        "Config field " & name & "[" & $i & "] must be a string."
      )
    values.add(item.getStr())

proc readConfigString(node: JsonNode, name: string, value: var string) =
  ## Reads one optional string config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JString:
    raise newException(
      BigAdventureError,
      "Config field " & name & " must be a string."
    )
  value = item.getStr()

proc readConfigInt(node: JsonNode, name: string, value: var int) =
  ## Reads one optional integer config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JInt:
    raise newException(
      BigAdventureError,
      "Config field " & name & " must be an integer."
    )
  value = item.getInt()

proc isKnownConfigField(name: string): bool =
  ## Returns true when a JSON config field is supported.
  case name
  of "seed",
      "maxTicks",
      "max-ticks",
      "maxGames",
      "max-games",
      "tokens",
      "profileTracePath",
      "profile-trace-path",
      "profileTicks",
      "profile-ticks":
    true
  else:
    false

proc validateConfigFields(node: JsonNode) =
  ## Raises when JSON config contains an unknown field.
  for name, _ in node.pairs:
    if not name.isKnownConfigField():
      raise newException(
        BigAdventureError,
        "Unknown config field: " & name
      )

proc update(config: var RunConfig, jsonText: string) =
  ## Updates the CLI config from JSON.
  if jsonText.len == 0:
    return
  var node: JsonNode
  try:
    node = fromJson(jsonText)
  except jsony.JsonError as e:
    raise newException(
      BigAdventureError,
      "Could not parse config JSON: " & e.msg
    )
  if node.kind != JObject:
    raise newException(BigAdventureError, "Config must be a JSON object.")
  node.validateConfigFields()
  node.readConfigString("profileTracePath", config.profileTracePath)
  node.readConfigString("profile-trace-path", config.profileTracePath)
  node.readConfigInt("seed", config.seed)
  node.readConfigInt("maxTicks", config.maxTicks)
  node.readConfigInt("max-ticks", config.maxTicks)
  node.readConfigInt("maxGames", config.maxGames)
  node.readConfigInt("max-games", config.maxGames)
  node.readConfigInt("profileTicks", config.profileTicks)
  node.readConfigInt("profile-ticks", config.profileTicks)
  node.readConfigStrings("tokens", config.tokens)

proc validate(config: RunConfig) =
  ## Raises when a run config value is outside the supported range.
  if config.maxTicks < 0:
    raise newException(
      BigAdventureError,
      "Config field maxTicks must be non-negative."
    )
  if config.maxGames < 0:
    raise newException(
      BigAdventureError,
      "Config field maxGames must be non-negative."
    )
  if config.profileTicks < 0:
    raise newException(
      BigAdventureError,
      "Config field profileTicks must be non-negative."
    )

proc limitText(value: int): string =
  ## Returns a readable text value for a numeric limit.
  if value > 0:
    $value
  else:
    "infinite"

proc echoStartupPaths(config: RunConfig, runtimeConfig: RuntimeConfig) =
  ## Prints configured replay and score output paths.
  echo "Big Adventure config: host=", config.address,
    " port=", config.port,
    " seed=", config.seed,
    " tokens=", config.tokens.len,
    " maxTicks=", config.maxTicks.limitText(),
    " maxGames=", config.maxGames.limitText()
  if runtimeConfig.replayMode:
    echo "Loading replay from runtime config."
  if runtimeConfig.replayUri.len > 0:
    echo "Writing replay target: " & runtimeConfig.replayUri
  if runtimeConfig.resultsUri.len > 0:
    echo "Writing results target: " & runtimeConfig.resultsUri
  if config.tokens.len > 0:
    echo "Using " & $config.tokens.len & " player connection tokens."
  else:
    echo "No player connection tokens configured."
  if config.profileTracePath.len > 0:
    echo "Writing profile trace: " & config.profileTracePath
    if config.profileTicks > 0:
      echo "Profile ticks: " & $config.profileTicks
    else:
      echo "Profile ticks: until shutdown"

when isMainModule:
  let runtimeConfig = readRuntimeConfig()
  var
    config = RunConfig(
      address: runtimeConfig.host,
      port: runtimeConfig.port,
      seed: 0xB1770,
      maxTicks: DefaultMaxTicks,
      maxGames: DefaultMaxGames,
      tokens: @[],
      profileTracePath: "",
      profileTicks: 0
    )
  config.update(runtimeConfig.config)
  config.validate()
  config.echoStartupPaths(runtimeConfig)
  let
    saveReplayPath =
      if runtimeConfig.replayUri.len > 0:
        getTempDir() / ("big-adventure-replay-" & $getCurrentProcessId() &
          ".bitreplay")
      else:
        ""
    loadReplayPath =
      if runtimeConfig.replayMode:
        let path = getTempDir() / ("big-adventure-load-replay-" &
          $getCurrentProcessId() & ".bitreplay")
        writeFile(path, runtimeConfig.replay)
        path
      else:
        ""
  runServerLoop(
    config.address,
    config.port,
    config.seed,
    saveReplayPath,
    loadReplayPath,
    runtimeConfig,
    config.tokens,
    config.maxTicks,
    config.maxGames,
    config.profileTracePath,
    config.profileTicks
  )
