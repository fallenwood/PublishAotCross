@echo off

set args=%*

rem Run zig objcopy
zig objcopy %args%

