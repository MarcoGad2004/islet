"""Builds Models/AntiSpoof.mlpackage from Minivision's Silent-Face-Anti-Spoofing (Apache-2.0).

The result is committed, so this only needs re-running to rebuild it. It joins the repo's two 80x80 MiniFASNet
models into one Core ML model: `crop27` (the face box scaled 2.7x, for MiniFASNetV2) and `crop40` (scaled 4.0x, for
MiniFASNetV1SE), both BGR 0-255 like the originals. `live` is the two models' mean probability of a real face.

    python3 -m venv venv && venv/bin/pip install torch==2.5.1 coremltools==8.3.0 "numpy<2" pillow
    git clone https://github.com/minivision-ai/Silent-Face-Anti-Spoofing repo
    venv/bin/python scripts/convert-antispoof.py repo Models/AntiSpoof.mlpackage
"""
import os
import sys

import numpy as np
import torch
import torch.nn.functional as F

repo, out = sys.argv[1], sys.argv[2]
sys.path.insert(0, repo)
from src.model_lib.MiniFASNet import MiniFASNetV1SE, MiniFASNetV2  # noqa: E402

import coremltools as ct  # noqa: E402

WEIGHTS = os.path.join(repo, "resources", "anti_spoof_models")


def load(cls, name):
    model = cls(conv6_kernel=(5, 5))  # get_kernel(80, 80)
    state = torch.load(os.path.join(WEIGHTS, name), map_location="cpu", weights_only=True)
    model.load_state_dict({k.removeprefix("module."): v for k, v in state.items()})
    return model.eval()


class Both(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.a = load(MiniFASNetV2, "2.7_80x80_MiniFASNetV2.pth")
        self.b = load(MiniFASNetV1SE, "4_0_0_80x80_MiniFASNetV1SE.pth")

    def forward(self, crop27, crop40):
        pa = F.softmax(self.a(crop27), dim=1)
        pb = F.softmax(self.b(crop40), dim=1)
        return ((pa + pb) / 2)[:, 1]


model = Both().eval()
example = (torch.rand(1, 3, 80, 80) * 255, torch.rand(1, 3, 80, 80) * 255)
traced = torch.jit.trace(model, example)
image = dict(shape=(1, 3, 80, 80), color_layout=ct.colorlayout.BGR, scale=1.0)
ml = ct.convert(
    traced,
    inputs=[ct.ImageType(name="crop27", **image), ct.ImageType(name="crop40", **image)],
    outputs=[ct.TensorType(name="live")],
    minimum_deployment_target=ct.target.macOS14,
    compute_precision=ct.precision.FLOAT32,
)
ml.short_description = "Silent-Face-Anti-Spoofing MiniFASNetV2 (2.7x) + MiniFASNetV1SE (4.0x): probability the face is real."
ml.license = "Apache-2.0, Minivision (github.com/minivision-ai/Silent-Face-Anti-Spoofing)"
ml.save(out)

# Check the Core ML model gives the PyTorch answer on random input.
x = (np.random.rand(80, 80, 3) * 255).astype(np.uint8), (np.random.rand(80, 80, 3) * 255).astype(np.uint8)
with torch.no_grad():
    want = model(*[torch.from_numpy(i.transpose(2, 0, 1)).float()[None] for i in x]).item()
from PIL import Image  # noqa: E402

# PIL images are RGB; Core ML swaps to BGR for the model, as the camera crops will be.
got = ml.predict({"crop27": Image.fromarray(x[0][:, :, ::-1]), "crop40": Image.fromarray(x[1][:, :, ::-1])})["live"]
print(f"torch {want:.4f} coreml {float(np.ravel(got)[0]):.4f}")
