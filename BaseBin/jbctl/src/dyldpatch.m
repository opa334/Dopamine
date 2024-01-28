#include <choma/CSBlob.h>
#include <choma/Host.h>

char gDopamineUUID[] = (char[]){'D', 'O', 'P', 'A', 'M', 'I', 'N', 'E', 'D', 'O', 'P', 'A', 'M', 'I', 'N', 'E' };

int apply_dyld_patch(const char *dyldPath)
{
	MachO *dyldMacho = macho_init_for_writing(dyldPath);
	if (!dyldMacho) return -1;

	// Make AMFI flags always be `0xdf`, allows DYLD variables to always work
	__block uint64_t getAMFIAddr = 0;
	macho_enumerate_symbols(dyldMacho, ^(const char *name, uint8_t type, uint64_t vmaddr, bool *stop){
		if (!strcmp(name, "__ZN5dyld413ProcessConfig8Security7getAMFIERKNS0_7ProcessERNS_15SyscallDelegateE")) {
			getAMFIAddr = vmaddr;
		}
	});
	uint32_t getAMFIPatch[] = {
		0xd2801be0, // mov x0, 0xdf
		0xd65f03c0  // ret
	};
	macho_write_at_vmaddr(dyldMacho, getAMFIAddr, sizeof(getAMFIPatch), getAMFIPatch);

	// iOS 16+: Change LC_UUID to prevent the kernel from using the in-cache dyld
	macho_enumerate_load_commands(dyldMacho, ^(struct load_command loadCommand, uint64_t offset, void *cmd, bool *stop) {
		if (loadCommand.cmd == LC_UUID) {
			struct uuid_command *uuidCommand = (struct uuid_command *)cmd;
			memcpy(&uuidCommand->uuid, gDopamineUUID, sizeof(gDopamineUUID));
			macho_write_at_offset(dyldMacho, offset, loadCommand.cmdsize, uuidCommand);
			*stop = true;
		}
	});

	macho_free(dyldMacho);
	return 0;
}