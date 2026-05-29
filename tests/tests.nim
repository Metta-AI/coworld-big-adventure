import
  std/os,
  bitworld/spriteprotocol,
  bitworld/server,
  big_adventure/global,
  big_adventure/sim

const
  RootDir = currentSourcePath.parentDir.parentDir
  ScorePanelDigitSpriteBaseForTest = 18300
  ScorePanelPipSpriteBaseForTest = 18400
  ScorePanelNameSpriteBaseForTest = 18500
  ScorePanelPipObjectBaseForTest = 14000
  ScorePanelDigitObjectBaseForTest = 15000
  ScorePanelNameObjectBaseForTest = 17000
  ScorePanelMaxScoreCharsForTest = 16
  PlayerViewportWidthForTest = 320
  PlayerViewportHeightForTest = 200

proc findViewport(
  viewports: openArray[SpritePacketViewport],
  layer: int
): SpritePacketViewport =
  ## Returns one viewport by layer or fails the test.
  for item in viewports:
    if item.layer == layer:
      return item
  doAssert false, "missing sprite protocol viewport"

proc findObject(
  objects: openArray[SpritePacketObject],
  objectId: int
): SpritePacketObject =
  ## Returns one object by id or fails the test.
  for item in objects:
    if item.id == objectId:
      return item
  doAssert false, "missing sprite protocol object"

proc initBigAdventureForTest(seed = 1234): SimServer =
  ## Initializes Big Adventure from its asset directory.
  let previousDir = getCurrentDir()
  setCurrentDir(RootDir)
  try:
    result = initSimServer(seed)
  finally:
    setCurrentDir(previousDir)

proc hasCoinPickup(sim: SimServer, value: int): bool =
  ## Returns true when a coin pickup with the given value exists.
  for pickup in sim.pickups:
    if pickup.kind == PickupCoin and pickup.value == value:
      return true

proc testPlayerDropsCarriedCoinsOnDeath() =
  ## Checks that player death drops all carried coins before reset.
  var sim = initBigAdventureForTest()
  sim.mobs.setLen(0)
  sim.pickups.setLen(0)

  let
    attacker = sim.addPlayer("attacker")
    victim = sim.addPlayer("victim")
    dropValue = 17
  sim.players[attacker].x = WorldWidthPixels div 2
  sim.players[attacker].y = WorldHeightPixels div 2
  sim.players[attacker].facing = FaceRight
  sim.players[attacker].bounds = sim.playerBoundsFor(sim.players[attacker])

  sim.players[victim].x = sim.players[attacker].x + 24
  sim.players[victim].y = sim.players[attacker].y
  sim.players[victim].bounds = sim.playerBoundsFor(sim.players[victim])
  sim.players[victim].lives = 1
  sim.players[victim].coins = dropValue

  sim.step([InputState(attack: true), InputState()])

  doAssert sim.players[victim].lives == MaxPlayerLives,
    "dead player should respawn with full lives"
  doAssert sim.players[victim].coins == 0,
    "dead player should lose carried coins"
  doAssert sim.hasCoinPickup(dropValue),
    "death should drop one coin pickup worth all carried coins"

proc testMobsAvoidPlayerStart() =
  ## Checks that initial mobs do not spawn near the player start area.
  let sim = initBigAdventureForTest()
  let
    centerX = (WorldWidthTiles div 2) * WorldTileSize + WorldTileSize div 2
    centerY = (WorldHeightTiles div 2) * WorldTileSize + WorldTileSize div 2
    safeRadiusSq = MobSpawnSafeRadius * MobSpawnSafeRadius

  doAssert sim.mobs.len > 0, "test world should start with mobs"
  for mob in sim.mobs:
    let
      mobX = boundsCenterX(mob.x, mob.bounds)
      mobY = boundsCenterY(mob.y, mob.bounds)
    doAssert distanceSquared(mobX, mobY, centerX, centerY) > safeRadiusSq,
      "initial mob should not spawn near player start"

proc testMobSightRadiusIsSmaller() =
  ## Checks that mobs only chase players once they are close by.
  doAssert MobSightRadius == (WorldTileSize * 3) div 2,
    "mob sight radius should be half of the earlier three-tile radius"

proc testPlayerSpeedIsSlower() =
  ## Checks that player top speed is 25 percent slower.
  doAssert MaxSpeed == 264, "player max speed should be 25 percent slower"

proc testGlobalScorePanelRenders() =
  ## Checks that the global view includes the coin score panel.
  var sim = initBigAdventureForTest()
  let
    red = sim.addPlayer("red")
    blue = sim.addPlayer("blue")
    redId = sim.players[red].id
    blueId = sim.players[blue].id
  sim.players[red].coins = 4
  sim.players[blue].coins = 12

  var nextState: GlobalViewerState
  let packet = sim.buildSpriteProtocolUpdates(
    initGlobalViewerState(),
    nextState
  )
  let
    objects = packet.spritePacketObjects()
    objectIds = packet.spritePacketObjectIds()
    spriteIds = packet.spritePacketSpriteIds()
    redNameObject = ScorePanelNameObjectBaseForTest + redId
    blueNameObject = ScorePanelNameObjectBaseForTest + blueId
    bluePipObject = ScorePanelPipObjectBaseForTest + blueId
    blueFirstDigit = ScorePanelDigitObjectBaseForTest +
      blueId * ScorePanelMaxScoreCharsForTest
    blueSecondDigit = blueFirstDigit + 1
  doAssert redNameObject in objectIds,
    "global view should include the red name object"
  doAssert blueNameObject in objectIds,
    "global view should include the blue name object"
  doAssert bluePipObject in objectIds,
    "global view should include the blue pip object"
  doAssert blueFirstDigit in objectIds,
    "global view should include the first blue score digit"
  doAssert blueSecondDigit in objectIds,
    "global view should include the second blue score digit"
  doAssert objects.findObject(blueNameObject).y <
    objects.findObject(redNameObject).y,
    "highest score should be first in the score panel"
  doAssert ScorePanelDigitSpriteBaseForTest + 1 in spriteIds,
    "global view should define the score digit sprite"
  doAssert ScorePanelPipSpriteBaseForTest + blueId in spriteIds,
    "global view should define the blue score pip sprite"
  doAssert ScorePanelNameSpriteBaseForTest + redId in spriteIds,
    "global view should define the red score name sprite"

  var cachedState: GlobalViewerState
  let cachedPacket = sim.buildSpriteProtocolUpdates(nextState, cachedState)
  let cachedSpriteIds = cachedPacket.spritePacketSpriteIds()
  doAssert ScorePanelDigitSpriteBaseForTest + 1 notin cachedSpriteIds,
    "unchanged score digit sprites should not be sent again"
  doAssert ScorePanelPipSpriteBaseForTest + blueId notin cachedSpriteIds,
    "unchanged score pip sprites should not be sent again"
  doAssert ScorePanelNameSpriteBaseForTest + redId notin cachedSpriteIds,
    "unchanged score name sprites should not be sent again"

proc testScorePanelNameSelectsPlayerPov() =
  ## Checks that score panel names toggle player point of view.
  var sim = initBigAdventureForTest()
  let
    red = sim.addPlayer("red")
    blue = sim.addPlayer("blue")
    blueId = sim.players[blue].id
    blueNameObject = ScorePanelNameObjectBaseForTest + blueId
  sim.players[red].coins = 4
  sim.players[blue].coins = 12

  var globalState: GlobalViewerState
  let globalPacket = sim.buildSpriteProtocolUpdates(
    initGlobalViewerState(),
    globalState
  )
  let blueName = globalPacket.spritePacketObjects().findObject(blueNameObject)

  var clickState = globalState
  clickState.mouseLayer = TopLeftLayerId
  clickState.mouseX = blueName.x
  clickState.mouseY = blueName.y
  clickState.clickPending = true

  var povState: GlobalViewerState
  let povPacket = sim.buildSpriteProtocolUpdates(clickState, povState)
  doAssert povState.selectedPlayerId == blueId,
    "clicking a score panel name should select that player"
  doAssert povState.povActive,
    "selecting a score panel name should enter player point of view"
  doAssert povState.povPlayerId == blueId,
    "point of view should track the selected player id"
  doAssert MapObjectId in povPacket.spritePacketObjectIds(),
    "player point of view should include the player camera map object"
  doAssert blueNameObject in povPacket.spritePacketObjectIds(),
    "player point of view should keep score panel names clickable"

  var clearState = povState
  clearState.mouseLayer = TopLeftLayerId
  clearState.mouseX = blueName.x
  clearState.mouseY = blueName.y
  clearState.clickPending = true

  var nextState: GlobalViewerState
  discard sim.buildSpriteProtocolUpdates(clearState, nextState)
  doAssert nextState.selectedPlayerId == -1,
    "clicking the selected score panel name should clear selection"
  doAssert not nextState.povActive,
    "clearing selection should return to global view"

proc testPlayerViewUsesWideViewport() =
  ## Checks that player and global PoV views use a 320 by 200 viewport.
  var sim = initBigAdventureForTest()
  let playerIndex = sim.addPlayer("wide")

  var playerState: PlayerViewerState
  let playerPacket = sim.buildSpriteProtocolPlayerUpdates(
    playerIndex,
    initPlayerViewerState(),
    playerState
  )
  let playerViewport = playerPacket.spritePacketViewports().findViewport(
    MapLayerId
  )
  doAssert playerViewport.width == PlayerViewportWidthForTest,
    "player view should be 320 pixels wide"
  doAssert playerViewport.height == PlayerViewportHeightForTest,
    "player view should be 200 pixels high"

  var clickState = initGlobalViewerState()
  clickState.selectedPlayerId = sim.players[playerIndex].id
  var povState: GlobalViewerState
  let povPacket = sim.buildSpriteProtocolUpdates(clickState, povState)
  let povViewport = povPacket.spritePacketViewports().findViewport(MapLayerId)
  doAssert povViewport.width == PlayerViewportWidthForTest,
    "global point of view should be 320 pixels wide"
  doAssert povViewport.height == PlayerViewportHeightForTest,
    "global point of view should be 200 pixels high"

testPlayerDropsCarriedCoinsOnDeath()
testMobsAvoidPlayerStart()
testMobSightRadiusIsSmaller()
testPlayerSpeedIsSlower()
testGlobalScorePanelRenders()
testScorePanelNameSelectsPlayerPov()
testPlayerViewUsesWideViewport()
echo "All tests passed"
