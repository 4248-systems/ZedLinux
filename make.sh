# This is only for local testing

cd src
tar -czf - . | base64 > ../archive.b64
echo '#!/bin/bash' > ../ZedLinux-install.sh
echo 'base64 -d << "EOF" | tar -xz' >> ../ZedLinux-install.sh
cat ../archive.b64 >> ../ZedLinux-install.sh
echo 'EOF' >> ../ZedLinux-install.sh
echo 'bash install.sh' >> ../ZedLinux-install.sh
chmod +x ../ZedLinux-install.sh
cd ..
rm archive.b64

