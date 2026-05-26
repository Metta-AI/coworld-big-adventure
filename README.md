# Big Adventure

Cooperative Coworld adventure game where players explore, fight monsters,
collect loot, and decide whether to share or defect.

## Running

```bash
nimble build
./big_adventure --address:0.0.0.0 --port:8080
```

Open `http://localhost:8080/client/global` to spectate.

## Bot

The bundled Nim bot is `konrad`.

```bash
nim c --path:src players/konrad/konrad.nim
./players/konrad/konrad --address:localhost --port:8080
```
