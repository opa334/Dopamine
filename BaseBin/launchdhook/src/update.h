#ifndef UPDATE_H
#define UPDATE_H

int jbupdate_basebin(const char *basebinTarPath);
void jbupdate_finalize_stage1(const char *prevVersion, const char *newVersion);
void jbupdate_finalize_stage2(const char *prevVersion, const char *newVersion);

#endif