#include "virtrw.h"

void kreadbuf(uint64_t kaddr, void* output, size_t size)
{
	uint64_t endAddr = kaddr + size;
	uint32_t outputOffset = 0;
	unsigned char* outputBytes = (unsigned char*)output;
	
	for(uint64_t curAddr = kaddr; curAddr < endAddr; curAddr += 4)
	{
		uint32_t k = kread32(curAddr);

		unsigned char* kb = (unsigned char*)&k;
		for(int i = 0; i < 4; i++)
		{
			if(outputOffset == size) break;
			outputBytes[outputOffset] = kb[i];
			outputOffset++;
		}
		if(outputOffset == size) break;
	}
}

void kwritebuf(uint64_t kaddr, void* input, size_t size)
{
	uint64_t endAddr = kaddr + size;
	uint32_t inputOffset = 0;
	unsigned char* inputBytes = (unsigned char*)input;
	
	for(uint64_t curAddr = kaddr; curAddr < endAddr; curAddr += 4)
	{
		uint32_t toWrite = 0;
		int bc = 4;
		
		uint64_t remainingBytes = endAddr - curAddr;
		if(remainingBytes < 4)
		{
			toWrite = kread32(curAddr);
			bc = (int)remainingBytes;
		}
		
		unsigned char* wb = (unsigned char*)&toWrite;
		for(int i = 0; i < bc; i++)
		{
			wb[i] = inputBytes[inputOffset];
			inputOffset++;
		}

		kwrite32(curAddr, toWrite);
	}
}

uint16_t kread16(uint64_t kaddr)
{
	uint16_t outBuf;
	kreadbuf(kaddr, &outBuf, sizeof(uint16_t));
	return outBuf;
}

uint8_t kread8(uint64_t kaddr)
{
	uint8_t outBuf;
	kreadbuf(kaddr, &outBuf, sizeof(uint8_t));
	return outBuf;
}

void kwrite16(uint64_t kaddr, uint16_t val)
{
	kwritebuf(kaddr, &val, sizeof(uint16_t));
}

void kwrite8(uint64_t kaddr, uint8_t val)
{
	kwritebuf(kaddr, &val, sizeof(uint8_t));
}

uint64_t kread_ptr(uint64_t kaddr) {
    uint64_t ptr = kread64(kaddr);
    if ((ptr >> 55) & 1) {
        return ptr | 0xFFFFFF8000000000;
    }
    
    return ptr;
}
