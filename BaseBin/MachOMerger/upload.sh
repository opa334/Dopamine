set -e

PROJECT_NAME=MachOMerger
DEVICE=iPhoneXs.iOS15

make
ssh $DEVICE "rm -rf /var/jb/$PROJECT_NAME"
scp ./$PROJECT_NAME $DEVICE:/var/jb/$PROJECT_NAME