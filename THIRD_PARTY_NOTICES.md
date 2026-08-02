# Third-Party Notices

ZenVoice embeds the `whisper.cpp` and FluidAudio runtimes and lets the user
download reviewed speech model weights from a verified in-app catalogue.
ZenVoice does not bundle model weights in the repository or application.

This notice records the reviewed upstream source, pinned runtime revision, and
applicable licence text. It is not a licence for ZenVoice itself. ZenVoice is
proprietary, source-visible software governed by [`LICENSE`](LICENSE); the
third-party components below remain under their own licences.

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

## FluidAudio

- Project: `FluidInference/FluidAudio`
- Source revision: `88d6d8166880dee1ac7c32c80f8e10cd782f8ca8`
- Source: <https://github.com/FluidInference/FluidAudio>
- Licence: Apache License 2.0
- Licence text:
  <https://www.apache.org/licenses/LICENSE-2.0>

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this runtime except in compliance with the License. You may obtain a copy
of the License at <https://www.apache.org/licenses/LICENSE-2.0>. Unless
required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

## NVIDIA Parakeet Unified EN 0.6B CoreML model

- Model creator: NVIDIA
- Upstream model:
  [`nvidia/parakeet-unified-en-0.6b`](https://huggingface.co/nvidia/parakeet-unified-en-0.6b)
- CoreML conversion:
  [`FluidInference/parakeet-unified-en-0.6b-coreml`](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml)
- Download revision: `4252711f6f060f9a2f91e5f081a806d7f45eebd8`
- Variant: offline CoreML encoder, INT8 weights
- Licence: Creative Commons Attribution 4.0 International
- Licence text: <https://creativecommons.org/licenses/by/4.0/legalcode>

The Parakeet Unified model is provided by NVIDIA and converted to Core ML by
FluidInference. ZenVoice downloads the reviewed conversion directly to the
user's Mac and verifies its pinned file manifest before use. No endorsement by
NVIDIA or FluidInference is implied.

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

## Whisper-Hindi2Hinglish-Apex model weights

- Publisher: Oriserve
- Upstream model:
  [`Oriserve/Whisper-Hindi2Hinglish-Apex`](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Apex)
- ZenVoice GGML conversion:
  [`imYChaudhary22/zenvoice-hinglish-apex-ggml`](https://huggingface.co/imYChaudhary22/zenvoice-hinglish-apex-ggml)
- Download revision: `0c540ce8945ef96b2880f2d2c0d05ba419621171`
- Licence: Apache License 2.0
- Licence text:
  <https://www.apache.org/licenses/LICENSE-2.0>

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
