DEVICE=iPhone13Pro.Remote

ssh $DEVICE "rm -rf /var/mobile/Documents/Dopamine.tipa"
scp ./Dopamine/Dopamine.tipa $DEVICE:/var/mobile/Documents/Dopamine.tipa
ssh $DEVICE "/var/jb/basebin/jbctl update tipa /var/mobile/Documents/Dopamine.tipa"