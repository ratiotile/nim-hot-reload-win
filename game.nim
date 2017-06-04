# game logic file
#
# compile with `nim c --app:lib game`

import strfmt


{.pragma: rtl, exportc, dynlib, cdecl.}


# frameNum -- which number frame this is
# dt       -- time since last update (in seconds)
# total    -- total elapsed time (in seconds)
proc update*(frameNum: int; dt, total: float) {.rtl.} =
  echo "foo {0}: update() [#{1}] dt={2}".fmt(total.format("5.2f"), frameNum.format("03d"), dt)
