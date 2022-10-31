//
//  DriverKitClasses.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef DriverKitClasses_h
#define DriverKitClasses_h

#ifndef DK_DECLARE_CLASS
#define DK_DECLARE_CLASS(name) extern mach_port_t DKCLASS$$$##name;
#endif

DK_DECLARE_CLASS(IOUserServer)
DK_DECLARE_CLASS(IODispatchQueue)
DK_DECLARE_CLASS(IOBufferMemoryDescriptor)
DK_DECLARE_CLASS(IODMACommand)

#endif
