#!/bin/bash

python3.10 -m venv venv
source venv/bin/activate

cd scripts/fusesoc
pip install -e .

cd scripts/edalize
pip install -e .
