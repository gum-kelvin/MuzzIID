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
    parser.add_argument('--mean', type=float, nargs=3, required=True)
    parser.add_argument('--std', type=float, nargs=3, required=True)
    parser.add_argument('--display-name')
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
    shape = inputs[0].shape if len(inputs) == 1 else []
    if (len(shape) != 4 or shape[:2] != [1,3] or not isinstance(shape[2],int)
            or shape[2] != shape[3] or not 32 <= shape[2] <= 1024 or inputs[0].type != 'tensor(float)'):
        parser.error('Expected one fixed float32 [1,3,S,S] input, S=32..1024')
    output = outputs[0].shape if len(outputs) == 1 else []
    if (len(output) != 2 or output[0] != 1 or not isinstance(output[1],int)
            or not 32 <= output[1] <= 4096 or outputs[0].type != 'tensor(float)'):
        parser.error('Expected one float32 [1,D] output, D=32..4096')
    if not np.isfinite(args.mean).all() or not np.isfinite(args.std).all() or min(args.std) <= 0:
        parser.error('Invalid RGB normalization')
    size, dimensions = shape[2], output[1]
    vector = session.run(None, {inputs[0].name: np.zeros((1,3,size,size), dtype=np.float32)})[0]
    if not np.isfinite(vector).all() or np.linalg.norm(vector) < 1e-12:
        parser.error('Smoke inference returned an invalid embedding')
    target = pathlib.Path(__file__).resolve().parents[1] / 'android/app/src/main/assets/models'
    config = dict(schema=1, version=args.version, sha256=hashlib.sha256(args.model.read_bytes()).hexdigest(),
                  inputSize=size, dimensions=dimensions, mean=args.mean, std=args.std, research=True,
                  displayName=args.display_name or args.version, calibrated=False, matchThreshold=args.match,
                  uncertainThreshold=args.uncertain, minimumMargin=args.margin)
    if (target / 'embedder.onnx').exists() or (target / 'model.json').exists():
        parser.error('Model assets already exist; move the old artifact aside explicitly')
    shutil.copyfile(args.model, target / 'embedder.onnx')
    (target / 'model.json').write_text(json.dumps(config, indent=2) + '\n')
    print('Model packaged with calibrated=false. Validate field thresholds before enabling identification.')


if __name__ == '__main__':
    main()
