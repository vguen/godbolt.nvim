SHELL := fish
default:
	fennel --globals vim --compile fnl/godbolt/init.fnl > lua/godbolt/init.lua
	fennel --globals vim,gb-exports --compile fnl/godbolt/assembly.fnl > lua/godbolt/assembly.lua
	fennel --globals vim --compile fnl/godbolt/execute.fnl > lua/godbolt/execute.lua
	fennel --globals vim --compile fnl/godbolt/fuzzy.fnl > lua/godbolt/fuzzy.lua
clean:
	rm lua/godbolt/*
