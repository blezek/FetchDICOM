FetchDICOM is a program to interact with a DICOM server to fetch and push
images. Specifically, it uses the <a href="http://dicom.offis.de/dcmtk.php.en">dcmtk</a> to query and move images
from the server locally.

The program is written in Tcl/Tk and is packaged using the [StarKit](http://www.equi4.com/starkit/index.html) wrapping mechanism.  The basic mechanism for creating the executable is to invoke the [TclKit](http://www.equi4.com/tclkit/index.html) to wrap the source code into a executable with the TclKit embedded.

<pre>
sdx wrap FetchDICOM -runtime tclkit
</pre>

The distribution contains a basic Makefile with targets for Windows, Linux and Mac.

<pre>
make win
make linux
make macosx
</pre>

These make targets depend on having the StarKit and TclKit installed.

