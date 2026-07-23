# Third-Party Notices

ZenVoice currently embeds the `whisper.cpp` runtime and lets the user download
converted OpenAI Whisper model weights from the verified in-app catalogue.
ZenVoice does not bundle model weights in the repository or application.

This notice records the reviewed upstream source, pinned runtime revision, and
applicable licence text. It is not a licence for ZenVoice itself. ZenVoice
intentionally remains unlicensed and all rights are reserved until the owner
selects a public-distribution licence.

## whisper.cpp

- Project: `ggml-org/whisper.cpp`
- Runtime release: `v1.9.1`
- Source revision: `f049fff95a089aa9969deb009cdd4892b3e74916`
- Source: <https://github.com/ggml-org/whisper.cpp>
- Licence: MIT

```text
MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## OpenAI Whisper model weights

- Project: `openai/whisper`
- Converted download source: `ggerganov/whisper.cpp`
- Download revision: `5359861c739e955e79d9a303bcbc70fb988958b1`
- Upstream: <https://github.com/openai/whisper>
- Converted files: <https://huggingface.co/ggerganov/whisper.cpp>
- Licence: MIT

```text
MIT License

Copyright (c) 2022 OpenAI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Distribution rule

The current catalogue downloads reviewed model files directly to the user's
Mac after explicit confirmation and checksum verification. If a future release
bundles, mirrors, modifies, or sells access to model files, the provenance and
redistribution terms must be reviewed again for that exact artifact.
