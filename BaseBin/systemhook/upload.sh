set -e

PROJECT_NAME=systemhook.dylib
DEVICE=root@localhost
PORT=2223

make
ssh $DEVICE -p $PORT "rm -rf /var/jb/$PROJECT_NAME"
scp -P$PORT ./$PROJECT_NAME $DEVICE:/var/jb/$PROJECT_NAME
ssh $DEVICE -p $PORT "/var/jb/basebin/jbctl rebuild_trustcache"