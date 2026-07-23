# Third-Party Notices

ZenVoice currently embeds the `whisper.cpp` and `llama.cpp` runtimes and lets
the user download reviewed speech and text-refinement model weights from
verified in-app catalogues. ZenVoice does not bundle model weights in the
repository or application.

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

## llama.cpp

- Project: `ggml-org/llama.cpp`
- Runtime release: `b9637`
- Source revision: `aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3`
- Source: <https://github.com/ggml-org/llama.cpp>
- XCFramework SHA-256:
  `46c7dad871f804d82399ddcfeb54d23b6469888801fc35124d7e33e543a9bef7`
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

## Qwen2.5 Instruct refinement model weights

- Publisher: Qwen / Alibaba Cloud
- Fast model:
  [`Qwen2.5-0.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF)
- Fast revision: `9217f5db79a29953eb74d5343926648285ec7e67`
- Balanced model:
  [`Qwen2.5-1.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF)
- Balanced revision: `91cad51170dc346986eccefdc2dd33a9da36ead9`
- Licence: Apache License 2.0
- Licence text:
  <https://www.apache.org/licenses/LICENSE-2.0>
- Publisher licence files are linked from each in-app catalogue row.

Copyright 2024 Alibaba Cloud.

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use these files except in compliance with the License. You may obtain a copy
of the License at <https://www.apache.org/licenses/LICENSE-2.0>. Unless
required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

## Distribution rule

The current catalogues download reviewed model files directly to the user's
Mac after explicit confirmation and checksum verification. If a future release
bundles, mirrors, modifies, or sells access to model files, the provenance and
redistribution terms must be reviewed again for that exact artifact.
