# Hot Reloading in Nim (Live Coding)

The objective is to be able to recompile code in a running application to see the changes immediately, without having to restart the program and lose the current running state. This is accomplished by keeping behavioral functions in a separate .dll, which can be reloaded when the code changes.

I started with this tutorial: https://16bpp.net/page/hot-loading-code-in-nim

## Getting it to compile

The first thing I noticed is that it doesn't compile. I installed `stopwatch` with nimble, but it apparently installs the wrong fork now (rbmz's). To fix this, install stopwatch from the respository: `nimble install https://gitlab.com/define-private-public/stopwatch`. Nimble is smart enough to figure out how to download and install from the url directly. I also had to update the path to nim for windows.

## DLL recompilation is broken

Now runner.nim compiles and runs, but the live compilation of game.nim isn't working. It gets stuck after it prints:

    Waiting for the DLL to be loaded...
    Write detected on game.nim

I tracked the problem down to the `waitForExit` call in the lines:

    # if so, try compile it
    let
      compile = startProcess(nimEXE, "", ["c", "--app:lib", name])
      compileStatus = waitForExit(compile)    # TODO maybe should have a timeout
    close(compile)

It seems that the compile never completes, but it is in another thread so we never get to see any console output which might indicate the problem. When I run the same command, `C:\nim\bin\nim c --app:lib game` in minimal nim program using `osproc.execCmd`, it works and prints out the compiler messages too. I tried debugging the code. Maybe waitForExit didn't need to be followed up with close? Nothing worked, until I changed the lines above to:

    let compileStatus = execCmd("nim c --app:lib game")
    echo "done compiling, status: ", compileStatus

Now it works, and also prints the compiler status messages to the console. 

## Fixing the startProcess method

I wanted to see what was wrong with the `startProcess` method, so I added the following code to the original version of runner.nim, to echo the output stream of the compile process. `import streams` also needs to be added, or else you get a confusing error about readLine getting the wrong type.

    let exit_code = compile.peekExitCode()
    let outs = compile.outputStream()
    while exit_code == -1:
      var line = ""
      if not outs.readLine(line):
        break
      if line != "":
        echo line

Surprisingly, consuming the output stream makes `waitForExit` end. It seems that the original version was stalled because there were still unread lines in the output stream buffer. 

## Finally: Can't open game.dll for writing

Now that the runner program could compile game.nim -> game.dll, there was a problem with game.dll being in use, and the compiler failing because it was unable to overwrite it. Apparently, Windows will lock game.dll when loaded, preventing it from being deleted or overwritten. However, it is still possible to rename the file while in use. Before running the compiler, rename the dll so it is able to save the new game.dll:

    if existsFile("game.dll"):
      moveFile("game.dll", "game.dll.old")

Then the old file can be deleted after it has been unloaded:

    if existsFile("game.dll.old"):
      removeFile("game.dll.old")

Now hot reloading works!

# Extra: Compiling with Visual Studio in C++ mode

Compiling nim in C mode with msvc is very slow: ~20 seconds on my machine. Using the C++ backend speeds up considerably to ~2 seconds.

In Sublime Text 3, the nimlime plugin doesn't provide a c++ build mode, so I had to create one manually. Single quotes don't work, so escaped double quotes need to be used. && allows multiple commands on one line, which is needed, because Sublime only supports a single command line for a build system.

    {
        "shell_cmd": "\"c:\\Program Files (x86)\\Microsoft Visual Studio 14.0\\vc\\vcvarsall.bat\" x64 && nim cpp $file_base_name"
    }

I also created a nim.cfg file in the project directory to speed up compilation by specifying compiler and linker options:

    vcc.options.always = "/nologo /EHsc /MP"
    vcc.options.linker = "--platform:amd64 /nologo /DEBUG /Zi /F33554432 /incremental /debug:fastlink"

