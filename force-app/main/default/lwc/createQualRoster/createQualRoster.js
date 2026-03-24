import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchRecruitClassAndContacts from '@salesforce/apex/QualRosterController.searchRecruitClassAndContacts';
import getContactMembers             from '@salesforce/apex/QualRosterController.getContactMembers';
import addToRoster                   from '@salesforce/apex/QualRosterController.addToRoster';

export default class QualRosterTab extends LightningElement {

    // ── Recruit Class Lookup ───────────────────────────────────────────────
    @track selectedRecruitClass = null;
    @track lookupSearchKey      = '';
    @track showLookupDropdown   = false;
    @track isLookupSearching    = false;
    @track rcSearchResults      = [];
    @track contactSearchResults = [];
    lookupSearchTimeout;

    get hasRcResults()      { return this.rcSearchResults.length > 0; }
    get hasContactResults() { return this.contactSearchResults.length > 0; }
    get hasAnyResults()     { return this.hasRcResults || this.hasContactResults; }

    // ── Session fields ─────────────────────────────────────────────────────
    @track testDate           = '';
    @track firearmInstructor  = '';
    @track location           = '';
    @track lightningCondition = '';
    @track lcDaytime          = false;
    @track lcNighttime        = false;

    // ── Table ─────────────────────────────────────────────────────────────
    @track isLoadingMembers = false;
    @track tableSearchKey   = '';
    @track rowData          = [];
    selectedMemberIds       = new Set();

    // ── Computed ───────────────────────────────────────────────────────────
    get memberCount()   { return this.rowData.length; }
    get hasSelection()  { return this.selectedMemberIds.size > 0; }
    get selectedCount() { return this.selectedMemberIds.size; }

    get isAddDisabled() {
        return this.selectedMemberIds.size === 0 || !this.testDate;
    }

    get allSelected() {
        return this.rowData.length > 0 &&
               this.rowData.every(r => this.selectedMemberIds.has(r.memberId));
    }

    get filteredRows() {
        if (!this.tableSearchKey || !this.tableSearchKey.trim()) return this.rowData;
        const key = this.tableSearchKey.toLowerCase();
        return this.rowData.filter(r =>
            (r.contactName && r.contactName.toLowerCase().includes(key)) ||
            (r.tins        && r.tins.toLowerCase().includes(key))        ||
            (r.division    && r.division.toLowerCase().includes(key))
        );
    }

    // ── Lookup handlers ────────────────────────────────────────────────────
    handleLookupFocus() {
        if (this.lookupSearchKey && this.lookupSearchKey.trim().length >= 1) {
            this.showLookupDropdown = true;
        }
    }

    handleLookupSearch(event) {
        this.lookupSearchKey = event.target.value;
        clearTimeout(this.lookupSearchTimeout);

        if (!this.lookupSearchKey || this.lookupSearchKey.trim().length < 1) {
            this.showLookupDropdown   = false;
            this.rcSearchResults      = [];
            this.contactSearchResults = [];
            return;
        }

        this.isLookupSearching  = true;
        this.showLookupDropdown = true;

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.lookupSearchTimeout = setTimeout(() => {
            this.runLookupSearch(this.lookupSearchKey);
        }, 300);
    }

    runLookupSearch(key) {
        searchRecruitClassAndContacts({ searchKey: key })
            .then(result => {
                this.rcSearchResults = result.recruitClasses || [];
                this.contactSearchResults = (result.contacts || []).map(c => ({
                    ...c,
                    recruitClassId  : c.RecruitClassId,
                    recruitClassName: c.RecruitClassName,
                    tins            : c.TINS
                }));
                this.isLookupSearching = false;
            })
            .catch(error => {
                this.isLookupSearching = false;
                this.showErrorToast('Search failed: ' + this.reduceErrors(error));
            });
    }

    // onmousedown fires before blur — keeps dropdown open on item click
    handleLookupSelect(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        console.log('handleLookupSelect', id, name);
        if (!id) {
            this.showErrorToast('This contact has no linked Recruit Class.');
            return;
        }

        this.selectedRecruitClass = { Id: id, Name: name };
        this.lookupSearchKey      = '';
        this.showLookupDropdown   = false;
        this.rcSearchResults      = [];
        this.contactSearchResults = [];
        this.selectedMemberIds    = new Set();
        this.rowData              = [];
        this.tableSearchKey       = '';
        this.loadMembers(id);
    }

    handleClearClass() {
        this.selectedRecruitClass = null;
        this.lookupSearchKey      = '';
        this.showLookupDropdown   = false;
        this.rcSearchResults      = [];
        this.contactSearchResults = [];
        this.rowData              = [];
        this.selectedMemberIds    = new Set();
        this.tableSearchKey       = '';
    }

    // ── Load Members ───────────────────────────────────────────────────────
    // FAQP_Members__c fields:
    //   Id, Name, Contact__c, Contact__r.Name,
    //   Contact__r.TINS_NUMBER__c, Contact__r.FAQP_Division__c,
    //   Contact__r.FAQP_Region__c
    loadMembers(recruitClassId) {
        this.isLoadingMembers = true;
        getContactMembers({ recruitClassId })
            .then(members => {
                this.rowData          = members.map(m => this.buildRow(m));
                console.log('members', JSON.stringify(members));
                this.isLoadingMembers = false;
            })
            .catch(error => {
                this.isLoadingMembers = false;
                this.showErrorToast('Failed to load members: ' + this.reduceErrors(error));
            });
    }

    buildRow(m) {
        const contact = m.Contact__r || {};
        return {
            memberId    : m.Id,
            contactName : contact.Name   || '—',
            contactUrl  : m.Contact__c   ? `/lightning/r/Contact/${m.Contact__c}/view` : null,
            tins        : contact.TINS_NUMBER__c      || '',
            division    : contact.FAQP_Division__c    || '',
            region      : contact.FAQP_Region__c != null
                          ? String(contact.FAQP_Region__c) : '',
            pistol      : false,
            shotgun     : false,
            rifle       : false,
            isSelected  : false,
            rowClass    : 'member-row'
        };
    }

    // ── Session field handlers ─────────────────────────────────────────────
    handleTestDateChange(event)   { this.testDate          = event.target.value; }
    handleInstructorChange(event) { this.firearmInstructor = event.target.value; }
    handleLocationChange(event)   { this.location          = event.target.value; }

    handleLightningConditionChange(event) {
        this.lightningCondition = event.target.value;
        this.lcDaytime          = this.lightningCondition === 'DayTime/Norrmal Lighting';
        this.lcNighttime        = this.lightningCondition === 'NightTime/Reduced Lighting';
    }

    // ── Table search ───────────────────────────────────────────────────────
    handleTableSearch(event) { this.tableSearchKey = event.target.value; }

    // ── Row selection ──────────────────────────────────────────────────────
    handleSelectAll(event) {
        const checked = event.target.checked;
        this.rowData.forEach(r => {
            if (checked) this.selectedMemberIds.add(r.memberId);
            else         this.selectedMemberIds.delete(r.memberId);
        });
        this.refreshRowClasses();
    }

    handleRowCheck(event) {
        const memberId = event.target.dataset.memberId;
        if (event.target.checked) this.selectedMemberIds.add(memberId);
        else                      this.selectedMemberIds.delete(memberId);
        this.refreshRowClasses();
    }

    refreshRowClasses() {
        this.rowData = this.rowData.map(r => ({
            ...r,
            isSelected: this.selectedMemberIds.has(r.memberId),
            rowClass  : this.selectedMemberIds.has(r.memberId)
                        ? 'member-row row-selected' : 'member-row'
        }));
    }

    // ── Weapon checkbox ────────────────────────────────────────────────────
    handleWeaponCheck(event) {
        const memberId = event.target.dataset.memberId;
        const field    = event.target.dataset.field;
        const value    = event.target.checked;
        this.rowData = this.rowData.map(r =>
            r.memberId === memberId ? { ...r, [field]: value } : r
        );
    }

    // ── Add To Roster ──────────────────────────────────────────────────────
    handleAddToRoster() {
        if (!this.testDate) {
            this.showErrorToast('Please select a Test Date before adding to roster.');
            return;
        }
        if (!this.selectedMemberIds.size) {
            this.showErrorToast('Please select at least one member.');
            return;
        }

        const rosterPayload = this.rowData
            .filter(r => this.selectedMemberIds.has(r.memberId))
            .map(r => ({
                memberId           : r.memberId,
                pistol             : r.pistol  ? 'Yes' : 'No',
                shotgun            : r.shotgun ? 'Yes' : 'No',
                rifle              : r.rifle   ? 'Yes' : 'No',
                lightningCondition : this.lightningCondition
            }));

        addToRoster({
            rosterPayload    : JSON.stringify(rosterPayload),
            recruitClassId   : this.selectedRecruitClass.Id,
            testDate         : this.testDate,
            firearmInstructor: this.firearmInstructor,
            location         : this.location
        })
        .then(count => {
            this.showSuccessToast(`${count} FIR Form(s) created successfully!`);
            this.selectedMemberIds = new Set();
            this.loadMembers(this.selectedRecruitClass.Id);
        })
        .catch(error => {
            this.showErrorToast('Add to Roster failed: ' + this.reduceErrors(error));
        });
    }

    // ── Toast helpers ──────────────────────────────────────────────────────
    showSuccessToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success' }));
    }
    showErrorToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }

    reduceErrors(errors) {
        if (typeof errors === 'string') return errors;
        if (Array.isArray(errors)) {
            return errors.filter(e => !!e).map(e => {
                if (typeof e === 'string')           return e;
                if (e.message)                       return e.message;
                if (e.body && e.body.message)        return e.body.message;
                return JSON.stringify(e);
            }).join(', ');
        }
        if (errors?.body?.message) return errors.body.message;
        if (errors?.message)       return errors.message;
        return 'Unknown error';
    }
}