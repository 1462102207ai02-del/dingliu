#ifndef WDCatalog_h
#define WDCatalog_h

#import "WDCommon.h"

const WDItem *WDCatalogItems(void);
int WDCatalogCount(void);
const WDItem *WDCatalogFind(NSString *className);
int WDCatalogIndexOf(NSString *className);
NSString *WDGroupTitle(int group);
NSString *WDPageTitle(int page);
NSString *WDTabTitle(int page);
NSArray<NSNumber *> *WDCatalogIndexesForPage(int page);
NSArray<NSNumber *> *WDCatalogIndexesForGroup(int group);

#endif
