public class recruitClassController {
    @AuraEnabled(cacheable=true)
    public static List<Contact> searchContacts(String searchKey, Boolean selectedModel) {
        list<contact> searchcontacts = new list<contact>();
        system.debug('Search Contacts '+searchKey+' >> '+selectedModel);
        try{
            if(selectedModel){
                String key = searchKey + '%';        
                searchcontacts = [SELECT Id, firstName, LastName FROM Contact 
                                  WHERE  firstName LIKE :key
                                  ORDER BY Name LIMIT 50];
            }else{        
                searchcontacts = [SELECT Id, firstName, LastName FROM Contact ORDER BY Name LIMIT 50];
            }
            system.debug('searchcontacts '+searchcontacts);
        }catch(exception ex){
            
        }
        return searchcontacts;
    }
    
    @AuraEnabled
    public static void updateContactsWithRecruitClass(Id recruitClassId, List<Id> contactIds){
        try {
            List<Contact> searchcontacts = [SELECT Id,LastName,firstName, AccountId FROM Contact WHERE Id IN :contactIds];
            List<FAQP_Members__c> insertContactMembers = new List<FAQP_Members__c>();
            for(Contact c : searchcontacts){
                FAQP_Members__c cm = new FAQP_Members__c();
                cm.Contact__c = c.Id;
                cm.Recruit_Class__c = recruitClassId;
                cm.Name = c.LastName+' '+c.firstName;
                insertContactMembers.add(cm);
            }
            insert insertContactMembers;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<contact> findContacts( List<Map<String, String>> contactsData ) {
        if (contactsData == null || contactsData.isEmpty()) {
            throw new AuraHandledException('No data received');
        }
        
        List<contact> contactsList = new List<contact>();
        set<string> tins = new Set<string>();
        for (Map<String, String> row : contactsData) {
            string tinsNumber = row.get('tins');
            tins.add(tinsNumber);
        }
        system.debug('tinsnumber '+tins);
        if(!tins.isempty()){
            for(contact con: [select Id, firstName, LastName,TINS_NUMBER__c from contact where TINS_NUMBER__c IN: tins]){
                contactsList.add(con);
            }
        }
        
        system.debug('contactsList '+contactsList.size());
        return contactsList;
    }
    @AuraEnabled(cacheable=true)
    public static List<Account> getRecruitClasses() {
        return [
            SELECT Id, Name, FAQP_Recruit_model__c
            FROM Account where RecordType.Name ='FAQP_Account'
            ORDER BY CreatedDate DESC
        ];
    }
    
    @AuraEnabled
    public static Boolean recruitClassDupblicateCheck(string accName){
        try {
            List<Account> accList = [SELECT Id FROM Account WHERE Name = :accName AND RecordType.Name = 'FAQP_Account' LIMIT 1 ];
            return !accList.isEmpty();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}