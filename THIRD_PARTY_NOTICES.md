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
- Licence: Apache License 2.0 (see [Apache License 2.0](#apache-license-20))

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this runtime except in compliance with the License. Unless required by
applicable law or agreed to in writing, software distributed under the License
is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, either express or implied. See the License for the specific language
governing permissions and limitations under the License.

ZenVoice links the whole `FluidAudio` library product, so the components below
are compiled into the ZenVoice executable and are redistributed with it. They
are listed separately because their licences carry their own attribution
requirements.

### NemoTextProcessing (`text-processing-rs`)

Statically linked binary target used for NeMo text normalization.

- Project: `FluidInference/text-processing-rs`
- Release: `v0.3.0`
- Artifact: `NemoTextProcessing.xcframework.zip`
- SwiftPM checksum:
  `76d0ee9a32b1ee2193231299180ca9bc4fc7e98794e771b3d55d66498352d85f`
- Source: <https://github.com/FluidInference/text-processing-rs>
- Licence: Apache License 2.0 (see [Apache License 2.0](#apache-license-20))

That artifact statically links the following works:

- **NVIDIA NeMo Text Processing** — compiled weighted-FST grammars and
  text-normalization fixtures, pinned commit
  `1f1263579fe57ba7ed783cad3dddee710fcc5064`.
  <https://github.com/NVIDIA/NeMo-text-processing>. Apache License 2.0.
  Copyright (c) NVIDIA CORPORATION & AFFILIATES.
- **rustfst** — loads and executes the compiled OpenFST grammars.
  <https://github.com/Garvys/rustfst>. MIT OR Apache-2.0.
  Copyright (c) Alexandre Caulier and the rustfst contributors.
- **flate2** — decompresses the bundled gzipped grammars at load time.
  <https://github.com/rust-lang/flate2-rs>. MIT OR Apache-2.0.
  Copyright (c) Alex Crichton and the flate2 contributors.
- **Additional transitive Rust crates** reached through `rustfst` and
  `flate2` — for example `nom`, `miniz_oxide`, `bitflags`, and `anyhow` — each
  under MIT and/or Apache-2.0.

### fastcluster

Hierarchical clustering routines reached through `FastClusterWrapper`.

- Project: `fastcluster`
- Source: <https://danifold.net>
- Licence: BSD 2-Clause

This licence requires that binary redistributions reproduce the following
notice, which is why it appears here in full.

```text
Copyright:
  * Until package version 1.1.23: © 2011 Daniel Müllner <https://danifold.net>
  * All changes from version 1.1.24 on: © Google Inc. <https://www.google.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

### VBx

Speaker-clustering code derived from the VBx project.

- Project: VBx
- Licence: Apache License 2.0 (see [Apache License 2.0](#apache-license-20))
- Attribution: Copyright 2021-2024 BUT Speech@FIT (original VBx project)

## NVIDIA Parakeet Unified EN 0.6B CoreML model

- Model creator: NVIDIA
- Upstream model:
  [`nvidia/parakeet-unified-en-0.6b`](https://huggingface.co/nvidia/parakeet-unified-en-0.6b)
- CoreML conversion:
  [`FluidInference/parakeet-unified-en-0.6b-coreml`](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml)
- Download revision: `4252711f6f060f9a2f91e5f081a806d7f45eebd8`
- Variant: offline CoreML encoder, INT8 weights
- Licence: NVIDIA Open Model License — see the unresolved conflict below
- Licence text:
  <https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/>

**Licensed by NVIDIA Corporation under the NVIDIA Open Model License.**

The Parakeet model is provided by NVIDIA and converted to Core ML by
FluidInference. ZenVoice downloads the reviewed conversion directly to the
user's Mac and verifies its pinned file manifest before use. ZenVoice does not
redistribute the model weights. No endorsement by NVIDIA or FluidInference is
implied.

### Unresolved licence conflict

The upstream sources disagree about which NVIDIA model this conversion derives
from, and the two candidates are not under the same licence. Checked
2026-08-02:

| Source | States |
|---|---|
| The downloaded bundle's own `config.json` and `metadata.json`, at pinned revision `4252711f…` | `model_id: nvidia/parakeet-unified-en-0.6b` |
| [`nvidia/parakeet-unified-en-0.6b`](https://huggingface.co/nvidia/parakeet-unified-en-0.6b) | "Use of the model is governed by the NVIDIA Open Model License Agreement" |
| [`FluidInference/parakeet-unified-en-0.6b-coreml`](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml) model card | `cc-by-4.0`, with a model tree naming `nvidia/parakeet-tdt-0.6b-v2` as the base |
| [`nvidia/parakeet-tdt-0.6b-v2`](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) | "Use of this model is governed by the CC-BY-4.0 license" |

The artifact ZenVoice actually downloads identifies itself as the **unified**
model, which carries the NVIDIA Open Model License. The conversion repository
declares CC-BY-4.0, which matches the *other* NVIDIA model instead. ZenVoice
previously recorded CC-BY-4.0 by taking the conversion repository's declaration
at face value; the bundle's own metadata does not support that.

ZenVoice therefore records the NVIDIA Open Model License, because the artifact's
own identity is the stronger evidence and it is the stricter of the two terms.
Both candidate licences permit commercial use, redistribution and derivative
works with attribution, so this choice affects which notice is required rather
than whether the model may be used. If the publisher confirms the source is
`parakeet-tdt-0.6b-v2`, this section reverts to CC-BY-4.0. Obtaining that
confirmation is a release gate in
[`docs/RELEASE_READINESS.md`](docs/RELEASE_READINESS.md).

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
- Licence: Apache License 2.0 (see [Apache License 2.0](#apache-license-20))

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use these files except in compliance with the License. Unless required by
applicable law or agreed to in writing, software distributed under the License
is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, either express or implied. See the License for the specific language
governing permissions and limitations under the License.

## Apache License 2.0

The components above that are marked Apache License 2.0 are governed by the
following text. It is reproduced in full because Apache 2.0 requires
redistributions to be accompanied by a copy of the licence.

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute
          must include a readable copy of the attribution notices
          contained within such NOTICE file, excluding those notices
          that do not pertain to any part of the Derivative Works,
          in at least one of the following places: within a NOTICE text
          file distributed as part of the Derivative Works; within the
          Source form or documentation, if provided along with the
          Derivative Works; or, within a display generated by the
          Derivative Works, if and wherever such third-party notices
          normally appear. The contents of the NOTICE file are for
          informational purposes only and do not modify the License.
          You may add Your own attribution notices within Derivative Works
          that You distribute, alongside or as an addendum to the NOTICE
          text from the Work, provided that such additional attribution
          notices cannot be construed as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS
```

## Distribution rule

The current catalogues download reviewed model files directly to the user's
Mac after explicit confirmation and checksum verification. If a future release
bundles, mirrors, modifies, or sells access to model files, the provenance and
redistribution terms must be reviewed again for that exact artifact.
