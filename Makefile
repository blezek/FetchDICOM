

win:
	c:\\Projects\\bin\\tclkitsh c:\\Projects\\bin\\sdx.kit wrap FetchDICOM -runtime c:\\Projects\\bin\\tclkit.exe
	mv FetchDICOM FetchDICOM.exe


linux:
	sdx wrap FetchDICOM -runtime tclkit

macosx:
	sdx wrap FetchDICOM -runtime ./tclkit-macosx
