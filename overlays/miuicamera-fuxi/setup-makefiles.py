#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
from extract_utils.main import ExtractUtils
from extract_files import module

if __name__ == '__main__':
    utils = ExtractUtils.device(module)
    utils.run()
