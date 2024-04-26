#!/bin/bash

# Fail on any error
set -e

# Configuration
BASE_DIR=$(readlink -f "$(pwd)")
DEPLOYMENT_DIR="${BASE_DIR}/deploy_lsp8.app.stage"
BACKUP_DIR="${BASE_DIR}/backup_lsp8.app"
FRONTEND_LABEL="lsp8.app.frontend"
BACKEND_LABEL="lsp8.app.backend"
FRONTEND_PATH="${BASE_DIR}/${FRONTEND_LABEL}"
BACKEND_PATH="${BASE_DIR}/${BACKEND_LABEL}"

# Check necessary command availability
commands=(unzip tar gzip mv rm ln sed pm2 yarn)
for cmd in "${commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Required command $cmd is not installed. Aborting."; exit 1; }
done

# Functions
handle_error() {
    echo "Error: $1" >&2
    exit 1
}

backup_and_replace() {
    local label=$1 path=$2 deployment_dir=$3 backup_dir=$4
    local today
    today=$(date +%Y%m%d)
    tar czf "${backup_dir}/${today}-${label}.backup.tar.gz" -C "$path" .
    rm -rf "${path:?}" # Remove original safely
    mv "${deployment_dir}/${label}" "$BASE_DIR/"
}

# Begin deployment
echo "Starting deployment process."

# Unpack new deployment package
cd "$DEPLOYMENT_DIR"
unzip "$1.zip" || handle_error "Failed to unzip package"
cd "$BASE_DIR"

# Stop instances using PM2
pm2 delete $BACKEND_LABEL
pm2 delete $FRONTEND_LABEL

# Backup and replace directories
echo "Backing up and replacing directories."
backup_and_replace $BACKEND_LABEL "$BACKEND_PATH" "$DEPLOYMENT_DIR" "$BACKUP_DIR"
backup_and_replace $FRONTEND_LABEL "$FRONTEND_PATH" "$DEPLOYMENT_DIR" "$BACKUP_DIR"

# Setup and start backend
echo "Setting up backend."
cd "$BACKEND_PATH"
yarn install && yarn add sharp --ignore-engines
cd client-side && yarn install && yarn build
cd ../cache
rm -rf thumbnails
ln -s "$BASE_DIR/lsp8.app.thumbnails" thumbnails
cp "$BASE_DIR/.env-to-copy" ".env"
pm2 start yarn --name "$BACKEND_LABEL" -- start --restart-delay=1000

# Setup and start frontend
echo "Setting up frontend."
cd "$FRONTEND_PATH"
yarn install && yarn build
rm .env.local
sed -i'' -e "s|basePath: isProduction ? '/beta' : ''|basePath: isProduction ? '' : ''|" next.config.js
pm2 start yarn --name "$FRONTEND_LABEL" -- start

# Link frontend public folder to backend
cd "$BACKEND_PATH"
mv public public-v1
ln -s "$FRONTEND_PATH/public" public

# Finalize deployment
mv "$DEPLOYMENT_DIR/$1.zip" "$DEPLOYMENT_DIR/deployed"
echo "New version of lsp8.app deployed successfully."
