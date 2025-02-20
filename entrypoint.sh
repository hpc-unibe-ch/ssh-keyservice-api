#!/bin/bash
set -e
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt
python3 ssh_keyservice_api/seed_database.py
fastapi run ssh_keyservice_api/main.py
