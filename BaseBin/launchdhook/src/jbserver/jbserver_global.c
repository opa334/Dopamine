#include <libjailbreak/jbserver.h>

extern struct jbserver_domain gSystemwideDomain;
extern struct jbserver_domain gPlatformDomain;
extern struct jbserver_domain gWatchdogDomain;
extern struct jbserver_domain gRootDomain;
extern struct jbserver_domain gDopamineDomain;
extern struct jbserver_domain gRootHideDomain;

struct jbserver_impl gGlobalServer = {
	.maxDomain = 1,
	.domains = (struct jbserver_domain*[]){
		&gSystemwideDomain,
		&gPlatformDomain,
		&gWatchdogDomain,
		&gRootDomain,
		&gDopamineDomain,
		&gRootHideDomain,
		NULL,
	}
};