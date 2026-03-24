/**
 * QualRosterController .cls
 *
 * Object/Field API names per actual org schema:
 *  - Junction object  : FAQP_Members__c
 *  - FIR Form         : FIR_Qualification_Form__c
 *  - Weapon detail    : FIR_Weapon_Qualification_Detail__c
 *  - Weapon type      : Weapon_Type__c
 *  - Instructor field : Firearms_Instrutor__c  (typo in org — kept as-is)
 *  - Contact TINS     : TINS_NUMBER__c
 *  - Contact Division : FAQP_Division__c
 *  - Contact Region   : FAQP_Region__c
 *  - Contact RC lookup: Recruit_Class__c  → Recruit_Class__c object
 *  - RC object        : Recruit_Class__c  (custom, NOT Account)
 */
public with sharing class QualRosterController  {

    // ─── 1. Live Lookup — searches Recruit Classes AND Contacts ───────────
    @AuraEnabled(cacheable=true)
    public static SearchResultWrapper searchRecruitClassAndContacts(String searchKey) {
        SearchResultWrapper result = new SearchResultWrapper();
        if (String.isBlank(searchKey) || searchKey.trim().length() < 1) return result;

        String keyword = '%' + searchKey.trim() + '%';

        // Recruit Classes (custom object Recruit_Class__c)
        result.recruitClasses = [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE :keyword
            ORDER BY Name ASC
            LIMIT 10
        ];

        // Contacts — search by Name or TINS, must have a Recruit Class linked
        List<Contact> contacts = [
            SELECT Id, Name, TINS_NUMBER__c,
                   AccountId, Account.Name
            FROM Contact
            WHERE (Name LIKE :keyword OR TINS_NUMBER__c LIKE :keyword)
            AND AccountId != null
            ORDER BY Name ASC
            LIMIT 10
        ];

        for (Contact c : contacts) {
            ContactSearchItem item = new ContactSearchItem();
            item.Id               = c.Id;
            item.Name             = c.Name;
            item.TINS             = c.TINS_NUMBER__c;
            item.RecruitClassId   = c.AccountId;
            item.RecruitClassName = c.AccountId != null
                                    ? c.Account.Name : '';
            result.contacts.add(item);
        }
        return result;
    }

    // ─── 2. Contact Members for selected Recruit Class ─────────────────────
    @AuraEnabled(cacheable=false)
    public static List<FAQP_Members__c> getContactMembers(Id recruitClassId) {
        if (recruitClassId == null) return new List<FAQP_Members__c>();

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

    // ─── 3. Add To Roster ──────────────────────────────────────────────────
    // Per selected member:
    //   a. INSERT FIR_Qualification_Form__c
    //   b. INSERT FIR_Weapon_Qualification_Detail__c × 3 (Pistol / Shot Gun / Riffle)
    @AuraEnabled
    public static Integer addToRoster(
        String rosterPayload,
        Id     recruitClassId,
        Date   testDate,
        String firearmInstructor,
        String location
    ) {
        List<MemberPayload> payloadList =
            (List<MemberPayload>) JSON.deserialize(rosterPayload, List<MemberPayload>.class);

        if (payloadList == null || payloadList.isEmpty()) return 0;

        // Load FAQP_Members__c
        List<Id> memberIds = new List<Id>();
        for (MemberPayload mp : payloadList) memberIds.add(mp.memberId);

        Map<Id, FAQP_Members__c> memberMap = new Map<Id, FAQP_Members__c>([
            SELECT Id, Contact__c, Contact__r.Name
            FROM FAQP_Members__c
            WHERE Id IN :memberIds
        ]);

        // Resolve instructor name → User Id
        Id instructorId = null;
        if (String.isNotBlank(firearmInstructor)) {
            List<User> users = [
                SELECT Id FROM User
                WHERE Name LIKE :('%' + firearmInstructor.trim() + '%')
                AND IsActive = true
                LIMIT 1
            ];
            if (!users.isEmpty()) instructorId = users[0].Id;
        }

        // Build aligned lists
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

        // Build FIR_Weapon_Qualification_Detail__c — 3 per form
        List<FIR_Weapon_Qualification_Detail__c> weapons =
            new List<FIR_Weapon_Qualification_Detail__c>();

        for (Integer i = 0; i < aligned.size(); i++) {
            MemberPayload mp  = aligned[i];
            Id            fir = firForms[i].Id;

            weapons.add(new FIR_Weapon_Qualification_Detail__c(
                FIR_Qualification_Form__c = fir,
                Weapon_Type__c            = 'Pistol',
                Attempt_Date__c           = testDate
                //Qualified__c              = true
            ));
            weapons.add(new FIR_Weapon_Qualification_Detail__c(
                FIR_Qualification_Form__c = fir,
                Weapon_Type__c            = 'Shot Gun',
                Attempt_Date__c           = testDate
               // Qualified__c              = true
            ));
            weapons.add(new FIR_Weapon_Qualification_Detail__c(
                FIR_Qualification_Form__c = fir,
                Weapon_Type__c            = 'Riffle',
                Attempt_Date__c           = testDate
               // Qualified__c              = true
            ));
        }
        insert weapons;

        return aligned.size();
    }

    // ─── Wrapper classes ───────────────────────────────────────────────────
    public class MemberPayload {
        public String memberId;
        public String pistol;
        public String shotgun;
        public String rifle;
        public String lightningCondition;
    }

    public class SearchResultWrapper {
        @AuraEnabled public List<Account> recruitClasses = new List<Account>();
        @AuraEnabled public List<ContactSearchItem> contacts      = new List<ContactSearchItem>();
    }

    public class ContactSearchItem {
        @AuraEnabled public Id     Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String TINS;
        @AuraEnabled public Id     RecruitClassId;
        @AuraEnabled public String RecruitClassName;
    }
}