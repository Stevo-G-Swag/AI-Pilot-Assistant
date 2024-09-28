//
//  ai.c
//  ai
//
//  Created by MarBean Inc on 9/28/24.
//

#include <mach/mach_types.h>

kern_return_t ai_start(kmod_info_t * ki, void *d);
kern_return_t ai_stop(kmod_info_t *ki, void *d);

kern_return_t ai_start(kmod_info_t * ki, void *d)
{
    return KERN_SUCCESS;
}

kern_return_t ai_stop(kmod_info_t *ki, void *d)
{
    return KERN_SUCCESS;
}
