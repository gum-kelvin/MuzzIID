#!/usr/bin/env python3
"""Validate and package an exported embedding model; requires onnx + numpy + onnxruntime.
Never enables calibration automatically or downloads weights.
"""
import argparse
import hashlib
import json
import pathlib
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model', type=pathlib.Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--match', type=float, required=True)
    parser.add_argument('--uncertain', type=float, required=True)
    parser.add_argument('--margin', type=float, default=0.05)
    args = parser.parse_args()
    if not (-1 <= args.uncertain < args.match <= 1 and 0 <= args.margin <= 2):
        parser.error('Invalid cosine thresholds/margin')
    import onnx
    import numpy as np
    import onnxruntime as ort
    graph = onnx.load(str(args.model))
    onnx.checker.check_model(graph)
    session = ort.InferenceSession(str(args.model), providers=['CPUExecutionProvider'])
    inputs, outputs = session.get_inputs(), session.get_outputs()
    if len(inputs) != 1 or inputs[0].shape != [1, 3, 224, 224] or inputs[0].type != 'tensor(float)':
        parser.error('Expected one float32 [1,3,224,224] input')
    if len(outputs) != 1 or outputs[0].shape != [1, 512] or outputs[0].type != 'tensor(float)':
        parser.error('Expected one float32 [1,512] output')
    vector = session.run(None, {inputs[0].name: np.zeros((1, 3, 224, 224), dtype=np.float32)})[0]
    if not np.isfinite(vector).all() or np.linalg.norm(vector) < 1e-12:
        parser.error('Smoke inference returned an invalid embedding')
    target = pathlib.Path(__file__).resolve().parents[1] / 'android/app/src/main/assets/models'
    config = dict(schema=1, version=args.version, sha256=hashlib.sha256(args.model.read_bytes()).hexdigest(),
                  inputSize=224, dimensions=512, calibrated=False, matchThreshold=args.match,
                  uncertainThreshold=args.uncertain, minimumMargin=args.margin)
    if (target / 'embedder.onnx').exists() or (target / 'model.json').exists():
        parser.error('Model assets already exist; move the old artifact aside explicitly')
    shutil.copyfile(args.model, target / 'embedder.onnx')
    (target / 'model.json').write_text(json.dumps(config, indent=2) + '\n')
    print('Model packaged with calibrated=false. Validate field thresholds before enabling identification.')


if __name__ == '__main__':
    main()
