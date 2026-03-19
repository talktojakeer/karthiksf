public with sharing class QualRosterController {

    // ─── 1. Recruit Classes ────────────────────────────────────────────────
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

    // ─── 2. Contact Members ────────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<Contact_Member__c> getContactMembers(Id recruitClassId) {
        if (recruitClassId == null) return new List<Contact_Member__c>();

        return [
            SELECT
                Id, Name,
                Contact__c,
                Contact__r.Name,
                Contact__r.FIR_Form__c,
                TINS__c,
                Division__c,
                Region__c,
                Recruit_Class__c
            FROM Contact_Member__c
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

        // Load Contact_Member__c
        List<Id> memberIds = new List<Id>();
        for (MemberPayload mp : payloadList) memberIds.add(mp.memberId);

        Map<Id, Contact_Member__c> memberMap = new Map<Id, Contact_Member__c>([
            SELECT Id, Contact__c, Contact__r.Name
            FROM Contact_Member__c
            WHERE Id IN :memberIds
        ]);

        // Resolve instructor name → User Id
        Id instructorId = null;
        if (String.isNotBlank(firearmInstructor)) {
            List<User> users = [
                SELECT Id FROM User
                WHERE Name LIKE :('%' + firearmInstructor.trim() + '%')
                AND IsActive = true LIMIT 1
            ];
            if (!users.isEmpty()) instructorId = users[0].Id;
        }

        // Build aligned lists
        List<MemberPayload> aligned  = new List<MemberPayload>();
        List<FIR_Form__c>   firForms = new List<FIR_Form__c>();

        for (MemberPayload mp : payloadList) {
            Contact_Member__c m = memberMap.get(mp.memberId);
            if (m == null) continue;
            aligned.add(mp);
            FIR_Form__c fir = new FIR_Form__c(
                Name         = (m.Contact__r != null ? m.Contact__r.Name : 'Member') + ' – FIR',
                Test_Date__c = testDate,
                Location__c  = location
            );
            if (instructorId != null) fir.Firearms_Instrutor__c = instructorId;
            firForms.add(fir);
        }
        insert firForms;

        // Build Weapon_Qualification__c
        // Pistol__c, Shot Gun, Riffle — Qualified__c = Yes means true
        List<Weapon_Qualification__c> weapons = new List<Weapon_Qualification__c>();
        for (Integer i = 0; i < aligned.size(); i++) {
            MemberPayload mp  = aligned[i];
            Id            fir = firForms[i].Id;

            // Pistol
            weapons.add(new Weapon_Qualification__c(
                FIR_Form__c     = fir,
                Weapon__c       = 'Pistol',
                Attempt_Date__c = testDate,
                Qualified__c    = mp.pistol == 'Yes'
            ));
            // Shot Gun
            weapons.add(new Weapon_Qualification__c(
                FIR_Form__c     = fir,
                Weapon__c       = 'Shot Gun',
                Attempt_Date__c = testDate,
                Qualified__c    = mp.shotgun == 'Yes'
            ));
            // Riffle
            weapons.add(new Weapon_Qualification__c(
                FIR_Form__c     = fir,
                Weapon__c       = 'Riffle',
                Attempt_Date__c = testDate,
                Qualified__c    = mp.rifle == 'Yes'
            ));
        }
        insert weapons;

        // Update Contact.FIR_Form__c
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < aligned.size(); i++) {
            Contact_Member__c m = memberMap.get(aligned[i].memberId);
            if (m == null) continue;
            contacts.add(new Contact(
                Id          = m.Contact__c,
                FIR_Form__c = firForms[i].Id
            ));
        }
        update contacts;

        return aligned.size();
    }

    // ─── Payload wrapper ───────────────────────────────────────────────────
    public class MemberPayload {
        public String memberId;
        public String pistol;
        public String shotgun;
        public String rifle;
        public String lightningCondition;
        public String qualAttempt;
    }
}