public with sharing class QualRosterController {

    @AuraEnabled(cacheable=true)
    public static SearchResultWrapper searchRecruitClassAndContacts(String searchKey) {
        SearchResultWrapper result = new SearchResultWrapper();
        if (String.isBlank(searchKey) || searchKey.trim().length() < 1) return result;

        String keyword = '%' + searchKey.trim() + '%';

        result.recruitClasses = [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE :keyword
            AND RecordType.DeveloperName = 'FAQP_Account'
            ORDER BY Name ASC
            LIMIT 10
        ];

        List<Contact> contacts = [
            SELECT Id, Name, TINS_NUMBER__c
            FROM Contact
            WHERE (Name LIKE :keyword OR TINS_NUMBER__c LIKE :keyword)
            ORDER BY Name ASC
            LIMIT 10
        ];

        for (Contact c : contacts) {
            ContactSearchItem item = new ContactSearchItem();
            item.Id   = c.Id;
            item.Name = c.Name;
            item.TINS = c.TINS_NUMBER__c;
            result.contacts.add(item);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserResult> searchUsers(String searchKey) {
        if (String.isBlank(searchKey) || searchKey.trim().length() < 1) {
            return new List<UserResult>();
        }
        String keyword = '%' + searchKey.trim() + '%';

        List<User> users = [
            SELECT Id, Name, Title
            FROM User
            WHERE Name LIKE :keyword
            AND IsActive = true
            ORDER BY Name ASC
            LIMIT 10
        ];

        List<UserResult> results = new List<UserResult>();
        for (User u : users) {
            UserResult ur = new UserResult();
            ur.Id    = u.Id;
            ur.Name  = u.Name;
            ur.Title = u.Title;
            results.add(ur);
        }
        return results;
    }

    @AuraEnabled(cacheable=false)
    public static List<FAQP_Members__c> getContactMembers(Id recruitClassId, Id contactId) {

        // Mode B — Contact selected
        if (contactId != null) {
            return [
                SELECT
                    Id, Name,
                    Contact__c,
                    Contact__r.Name,
                    Contact__r.TINS_NUMBER__c,
                    Contact__r.FAQP_Division__c,
                    Contact__r.FAQP_Region__c,
                    Recruit_Class__c
                FROM FAQP_Members__c
                WHERE Contact__c = :contactId
                ORDER BY Recruit_Class__r.Name ASC
                LIMIT 10
            ];
        }

        // Mode A — RC selected
        if (recruitClassId != null) {
            return [
                SELECT
                    Id, Name,
                    Contact__c,
                    Contact__r.Name,
                    Contact__r.TINS_NUMBER__c,
                    Contact__r.FAQP_Division__c,
                    Contact__r.FAQP_Region__c,
                    Recruit_Class__c
                FROM FAQP_Members__c
                WHERE Recruit_Class__c = :recruitClassId
                ORDER BY Contact__r.Name ASC
                LIMIT 500
            ];
        }

        return new List<FAQP_Members__c>();
    }

    // ─── 4. Add To Roster ──────────────────────────────────────────────────
    @AuraEnabled
    public static Integer addToRoster(
        String rosterPayload,
        Id     recruitClassId,
        Date   testDate,
        Id     instructorId,
        String location
    ) {
        List<MemberPayload> payloadList =
            (List<MemberPayload>) JSON.deserialize(rosterPayload, List<MemberPayload>.class);

        if (payloadList == null || payloadList.isEmpty()) return 0;

        List<Id> memberIds = new List<Id>();
        for (MemberPayload mp : payloadList) memberIds.add(mp.memberId);

        Map<Id, FAQP_Members__c> memberMap = new Map<Id, FAQP_Members__c>([
            SELECT Id, Contact__c, Contact__r.Name
            FROM FAQP_Members__c
            WHERE Id IN :memberIds
        ]);

        List<MemberPayload>             aligned  = new List<MemberPayload>();
        List<FIR_Qualification_Form__c> firForms = new List<FIR_Qualification_Form__c>();

        for (MemberPayload mp : payloadList) {
            FAQP_Members__c m = memberMap.get(mp.memberId);
            if (m == null) continue;
            aligned.add(mp);

            FIR_Qualification_Form__c fir = new FIR_Qualification_Form__c(
                Name         = (m.Contact__r != null ? m.Contact__r.Name : 'Member') + ' – FIR',
                Test_Date__c = testDate,
                Location__c  = location
            );
            if (instructorId != null) fir.Firearms_Instrutor__c = instructorId;
            firForms.add(fir);
        }
        insert firForms;

        // Only insert weapon records for weapons selected as Yes
        List<FIR_Weapon_Qualification_Detail__c> weapons =
            new List<FIR_Weapon_Qualification_Detail__c>();

        for (Integer i = 0; i < aligned.size(); i++) {
            Id            fir = firForms[i].Id;
            MemberPayload mp  = aligned[i];

            if (mp.pistol == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Pistol',
                    Attempt_Date__c           = testDate
                ));
            }
            if (mp.shotgun == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Shot Gun',
                    Attempt_Date__c           = testDate
                ));
            }
            if (mp.rifle == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Riffle',
                    Attempt_Date__c           = testDate
                ));
            }
            if (mp.autoWeapon == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Automatic Weapon',
                    Attempt_Date__c           = testDate
                ));
            }
            if (mp.precisionRifle == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Precision Riffle',
                    Attempt_Date__c           = testDate
                ));
            }
        }
        if (!weapons.isEmpty()) {
            insert weapons;
        }

        return aligned.size();
    }

    public class MemberPayload {
        public String memberId;
        public String pistol;
        public String shotgun;
        public String rifle;
        public String autoWeapon;
        public String precisionRifle;
        public String lightningCondition;
    }

    public class SearchResultWrapper {
        @AuraEnabled public List<Account>           recruitClasses = new List<Account>();
        @AuraEnabled public List<ContactSearchItem> contacts       = new List<ContactSearchItem>();
    }

    public class ContactSearchItem {
        @AuraEnabled public Id     Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String TINS;
    }

    public class UserResult {
        @AuraEnabled public Id     Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String Title;
    }
}