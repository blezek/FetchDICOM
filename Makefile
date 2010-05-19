

winall:
	c:\\Projects\\bin\\tclkitsh c:\\Projects\\bin\\sdx.kit wrap FetchDICOM -runtime c:\\Projects\\bin\\tclkit.exe
	mv FetchDICOM FetchDICOM.exe


linuxapp:
	sdx wrap FetchDICOM -runtime tclkit

macosx:
	../tclkit-darwin-univ-aqua ../sdx.kit wrap FetchDICOM -runtime ../tclkit-macosx
