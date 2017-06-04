# This runs the game
#
# compile with `nim c --threads:on runner`

import os, osproc, dynlib, locks, times, streams
import stopwatch


# Where your nim compiler is located
const nimEXE = "C:\\nim\\bin\\nim"
echo "nim path=", nimEXE


# Platform independant way of building a DLL path
proc buildDLLPath(name: string): string =
  when defined(windows):
    return name & ".dll"
  elif defined(macosx):
    return "./lib" & name & ".dylib"
  else:
    # Assume it's linux or UNIX
    return "./lib" & name & ".so"


# Proc prototype
type
  updateProc = proc (frameNum: int; dt, total: float) {.nimcall.}


# Global variables
var
  dll: LibHandle      # Library that's loaded
  update: updateProc  # Function to call, and reload
  dllReady = false    # DLL has been loaded or not
  running = true      # Running the "game,"

  # Locks for threading & flags
  dllLock: Lock
  dllReadyLock: Lock
  runningLock: Lock


# Setup the loading lock
initLock(dllLock)
initLock(dllReadyLock)
initLock(runningLock)


# Checks to see if a module/file has been changed, then  will recompile it and
# load the DLL.  It keeps on doing this until `running` has been set to `false`
# This proc should be run in its own thread.
proc loadDLL(name: string) {.thread.} =
  # Make some paths
  let
    dllPath = buildDLLPath(name)
    nimSrcPath = name & ".nim"

  var
    lastWriteTime = 0.Time
    isRunning = true

  while isRunning:
    # Check for change on .nim file
    var writeTime = 0.Time
    try:
      writeTime = getFileInfo(nimSrcPath).lastWriteTime
    except:
      discard

    if lastWriteTime < writeTime:
      echo "Write detected on " & nimSrcPath
      lastWriteTime = writeTime
      # if old dll exists, move it
      if existsFile("game.dll"):
        moveFile("game.dll", "game.dll.old")

      # if so, try compile it
      echo "compile", nimEXE, name
      let compile = startProcess(nimEXE, "", ["cpp", "--app:lib", name])

      # consume output
      let exit_code = compile.peekExitCode()
      let outs = compile.outputStream()
      while exit_code == -1:
        var line = ""
        if not outs.readLine(line):
          break
        if line != "":
          echo line
      echo "peek: ", exit_code

      let compileStatus = waitForExit(compile)    # TODO maybe should have a timeout
      #let compileStatus = execCmd("nim c --app:lib game")
      echo "done compiling, status: ", compileStatus
      close(compile)

      # if compilaiton was good, load the DLL
      if compileStatus == 0:
        # Get the lock
        acquire(dllLock)

        # unload the library if it has already been loaded
        if dll != nil:
          unloadLib(dll)
          dll = nil

        # (Re)load the library
        echo "Attempting to load " & dllPath
        dll = loadLib(dllPath)
        if dll != nil:
          let updateAddr = dll.symAddr("update")

          if updateAddr != nil:
            update = cast[updateProc](updateAddr)

            echo "Successfully loaded DLL & functions " & dllPath
            acquire(dllReadyLock)
            dllReady = true
            release(dllReadyLock)

            # delete old file
            if existsFile("game.dll.old"):
              removeFile("game.dll.old")

          else:
            echo "Error, Was able to load DLL, but not functions " & dllPath
        else:
          echo "Error, wasn't able to load DLL " & dllPath

        # Release the lock
        release(dllLock)
      else:
        # Bad compile, print a message
        echo nimSrcPath & " failed to compile; not reloading"

    # sleep for 1/5 of a second, then check for changes again
    sleep(200)

    # Check for quit
    acquire(runningLock)
    isRunning = running
    release(runningLock)


# Block until the DLL is loaded
proc waitForDLLReady() =
  echo "acquiring dll lock"
  acquire(dllReadyLock)
  var ready = dllReady
  echo "acquired dll lock"
  release(dllReadyLock)

  while not ready:
    # Test again every 1/5 second
    sleep(200)
    acquire(dllReadyLock)
    ready = dllReady
    release(dllReadyLock)


# Main game prodecedure and loop
proc main() =
  # Loading a DLL needs to be in it's own thread
  var dllLoadingThread: Thread[string]
  createThread(dllLoadingThread, loadDLL, "game")

  # Setup some of the game stuff
  var
    sw = stopwatch()
    lastFrameTime = 0.0
    frameCount = 0
    t = 0.0

  # Hold here until our DLLs are ready
  echo "Waiting for the DLL to be loaded..."
  waitForDLLReady()

  # Start the loop
  echo "Running for 60 seconds..."
  sw.start()
  while t < 60.1:
    let delta = t - lastFrameTime
    if delta >= 0.5:
      # run a frame
      update(frameCount, delta, t)

      # Set next
      lastFrameTime = t
      frameCount += 1

    t = sw.secs

  echo "Shutting down."

  # Cleanup our threads
  acquire(runningLock)
  running = false
  release(runningLock)
  joinThread(dllLoadingThread)


main()
