#!/bin/bash

# Prompt for the new name
read -p "Enter the new computer name: " name

# Confirm the name is not empty
if [ -z "$name" ]; then
  echo "No name entered. No changes made."
  exit 1
fi

# Apply the new name using scutil
echo "Setting computer name to '$name'..."
sudo scutil --set ComputerName "$name"
sudo scutil --set LocalHostName "$name"
sudo scutil --set HostName "$name"

echo "Name has been updated successfully."
