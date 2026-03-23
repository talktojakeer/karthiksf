public with sharing class QualRosterController {

    @AuraEnabled(cacheable=true)
    public static List<Account> getRecruitClasses() {
        Id rtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('FAQP_Account')
            .getRecordTypeId();

        return [
            SELECT Id, Name
            FROM Account
            WHERE RecordTypeId = :rtId
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=false)
    public static List<FAQP_Members__c> getContactMembers(Id recruitClassId) {
        if (recruitClassId == null) return new List<FAQP_Members__c>();

        return [
            SELECT
                Id, Name,
                Contact__c,
                Contact__r.Name,
                TINS__c,
                Division__c,
                Region__c,
                Recruit_Class__c
            FROM FAQP_Members__c
            WHERE Recruit_Class__c = :recruitClassId
            ORDER BY Contact__r.Name ASC
            LIMIT 500
        ];
    }

    @AuraEnabled
    public static Integer addToRoster(
        String   rosterPayload,
        Id       recruitClassId,
        Date     testDate,
        String   firearmInstructor,
        String   location
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

        Id instructorId = null;
        if (String.isNotBlank(firearmInstructor)) {
            List<User> users = [
                SELECT Id FROM User
                WHERE Name LIKE :('%' + firearmInstructor.trim() + '%')
                AND IsActive = true LIMIT 1
            ];
            if (!users.isEmpty()) instructorId = users[0].Id;
        }

        List<MemberPayload> aligned  = new List<MemberPayload>();
        List<FIR_Qualification_Form__c>   firForms = new List<FIR_Qualification_Form__c>();

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

        List<FIR_Weapon_Qualification_Detail__c> weapons = new List<FIR_Weapon_Qualification_Detail__c>();
        for (Integer i = 0; i < aligned.size(); i++) {
            MemberPayload mp  = aligned[i];
            Id            fir = firForms[i].Id;

            weapons.add(new FIR_Weapon_Qualification_Detail__c(
                FIR_Qualification_Form__c     = fir,
                Weapon_Type__c        = 'Pistol',
                Attempt_Date__c = testDate,
                Qualified__c    = 'Yes'
            ));

            weapons.add(new FIR_Weapon_Qualification_Detail__c(
                FIR_Qualification_Form__c     = fir,
                Weapon_Type__c        = 'Shot Gun',
                Attempt_Date__c = testDate,
                Qualified__c    = 'Yes'
            ));

            weapons.add(new FIR_Weapon_Qualification_Detail__c(
                FIR_Qualification_Form__c     = fir,
                Weapon_Type__c        = 'Riffle',
                Attempt_Date__c = testDate,
                Qualified__c    =  'Yes'
            ));
        }
        insert weapons;

        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < aligned.size(); i++) {
            FAQP_Members__c m = memberMap.get(aligned[i].memberId);
            if (m == null) continue;
            contacts.add(new Contact(
                Id          = m.Contact__c
               // FIR_Qualification_Form__c = firForms[i].Id
            ));
        }
        update contacts;

        return aligned.size();
    }

    public class MemberPayload {
        public String memberId;
        public String pistol;
        public String shotgun;
        public String rifle;
        public String lightningCondition;
        public String qualAttempt;
    }
}