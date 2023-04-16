set -e

PROJECT_NAME=forkfix.dylib
DEVICE=root@localhost
PORT=2222

make
ssh $DEVICE -p $PORT "rm -rf /var/jb/usr/lib/$PROJECT_NAME"
scp -P$PORT ./$PROJECT_NAME $DEVICE:/var/jb/usr/lib/$PROJECT_NAME
