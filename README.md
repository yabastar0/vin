
# vin kernel

![vinlogo](https://github.com/yabastar0/vin/blob/main/vin_optimized.png?raw=true)

**The vin kernel is a WIP**

## Kernel functions

`Kernel.setCursorPos(x:number, y:number)`\
Sets the cursor position\
\
`Kernel.getCursorPos():table`\
Returns a table containg the x and y position of the cursor\
\
`Kernel.setCursor(val:bool)`\
Sets whether the cursor is active or not. `true` to turn the cursor on, `false` to turn the cursor off.\
\
`Kernel.panic(err:str)`\
Is `error` before `error` is redefined to be much more stable\
\
`error(err:str)`\
Prints the error and the debug traceback\
\
`Kernel.busySleep(seconds:number)`\
Reccomended to not use this. This is the busy sleep form of `Kernel.sleep` and does not yield\
\
`Kernel.sleep(seconds:number)`\
Sleeps with proper yielding\
\
`computer.shutdown(reboot:bool)`\
The `shutdown` function rewritten with a reboot feature\
\
`Kernel.serialize(t:table [, opts:table]):str`\
Returns the string form of `t`. Options default to `{compact = false, allow_repetitions = false}`\
\
`Kernel.deserialize(str:str):table`\
Returns the table form of the string input\
\
`Kernel.inTable(value:any, tbl:table):bool`\
Returns true if the value appears in the table. Saves a few lines\
\
`Kernel.updateCursor()`\
This is ran by the kernel typically, but updates the cursor based on the data in `Kernel.cursor`\
\
`Kernel.http(request:table):many`\
Formatted `{type, url [, postData]}`.\
type is `get`, `post`, `request`, `checkURLAsync`, `checkURL`.\

## Kernel.term

`Kernel.term.setTextColor(color:number)`\
Sets the color of the foreground\
\
`Kernel.term.getTextColor():number`\
Gets the current color of the foreground\
\
`Kernel.term.setBackground(color:number)`\
Sets the color of the background\
\
`Kernel.term.getBackground():number`\
Gets the current color of the background\
\
`Kernel.term.get(x:number, y:number):string, number, number, number or nil, number or nil`\
Gets the character at x and y. The second and third returned values are the foreground and background colors. If the colors are from the palette, the fourth and fifth values specify the palette index of the color, otherwise nil.\
\
`Kernel.term.set(x:number, y:number, value:str)`\
Writes text to the screen at x and y with the current background and foreground colors.\
\
`Kernel.term.copy(x:number, y:number, w:number, h:number, tx:number, ty:number):bool`\
Copies data starting at x, y, w, h, to tx, ty. `true` on success\
\
`Kernel.term.fill(x:number, y:number, w:number, h:number, char:str):bool`\
Fills a rectangle starting at x, y to w, h with a char\
\
`Kernel.term.getGPU():gpu`\
Returns the gpu being used by the kernel\
\
`Kernel.term.setGPU(setGPU:gpu)`\
Sets the GPU being used by the kernel\
\
`Kernel.term.scrollUp()`\
Scrolls the term up by 1\
\
`Kernel.term.clear()`\
Clears the terminal with the current background color\
\
`Kernel.term.clearLine([line:number])`\
Clears the current line. If `line` is provided, clears the data on that line\
\

## Kernel.io

`Kernel.io.print(msg:str)`\
Prints a message onto the screen, behaves as one would expect\
\
`Kernel.io.write(msg:str)`\
Writes text, updates cursor, but no scrolling function\
\
`Kernel.io.writeChar(char:str)`\
Essentially the same as `io.write`. Slightly faster than it if writing a single char\
\
`Kernel.io.slowWrite(msg:str, delay:number)`\
Writes characters onto the display with a set delay between each character\
\

## Kernel variables

`_G.KERNELVER`\
The current version of the kernel\
\
`_G.OSVER`\
The current version of the OS\
\
`Kernel`\
Contains all of the kernel's global functions and variables\
\
`Kernel.term`\
Contains the term functions of the kernel\
\
`Kernel.io`\
Contains the io functions of the kernel\
\
`Kernel.cursor`\
Contains the cursor data, `pos`, `visible`, and `active`\
\
`Kernel.hasInternet`\
Contains a bool, whether or not an internet card was detected by `component.list("internet")()`
