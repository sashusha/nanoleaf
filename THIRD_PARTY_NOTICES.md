# Third-party notices

## Kelvin-to-RGB approximation

`Wire.rgb(kelvin:)` in `Sources/NanoleafCore/Core.swift` adapts Tanner Helland's
Kelvin-to-RGB approximation to Swift and the CLI's 2700–6500 K range.
The following BSD 2-Clause notice applies to that adaptation.

- Algorithm: https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html
- Author's code licensing statement: https://tannerhelland.com/code.html
- Upstream license: https://github.com/tannerhelland/vb6-code/blob/master/LICENSE.md

BSD 2-Clause License

Copyright (c) 2018, Tanner Helland
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Nanoleaf USB interoperability

This project implements USB protocol behavior documented by Nanoleaf and
streaming conventions established through inspection of its installed desktop
application and physical device tests. Nanoleaf application source files,
binaries, and libraries are not distributed with this project or loaded at runtime.
The included numerical hardware profile and its provenance are described in
[CALIBRATION.md](CALIBRATION.md).

Nanoleaf is referenced only to identify compatible hardware. This project is
independent and is not affiliated with or endorsed by Nanoleaf.
