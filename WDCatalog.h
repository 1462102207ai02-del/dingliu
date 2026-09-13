#ifndef WDCatalog_h
#define WDCatalog_h

#import "WDCommon.h"

const WDItem *WDCatalogItems(void);
int WDCatalogCount(void);
const WDItem *WDCatalogFind(NSString *className);
NSString *WDGroupTitle(int group);
NSArray<NSNumber *> *WDCatalogIndexesForGroup(int group);

#endif
