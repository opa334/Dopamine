DEVICE=root@localhost
PORT=2222

ssh $DEVICE -p $PORT "rm -rf /var/mobile/Documents/Dopamine.tipa"
scp -P$PORT ./Dopamine/Dopamine.tipa $DEVICE:/var/mobile/Documents/Dopamine.tipa
ssh $DEVICE -p $PORT "/var/jb/basebin/jbctl update tipa /var/mobile/Documents/Dopamine.tipa"