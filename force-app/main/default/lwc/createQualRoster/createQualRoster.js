import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecruitClasses from '@salesforce/apex/QualRosterController.getRecruitClasses';
import getContactMembers from '@salesforce/apex/QualRosterController.getContactMembers';
import addToRoster       from '@salesforce/apex/QualRosterController.addToRoster';

export default class CreateQualRoster extends LightningElement {

    // ── Recruit Class ──────────────────────────────────────────────────────
    @track recruitClasses       = [];
    @track selectedRecruitClass = null;
    @track showRcDropdown       = false;
    @track rcSearchKey          = '';
    @track isLoadingClasses     = false;
    allRecruitClasses           = [];

    // ── Session fields → FIR_Form__c ──────────────────────────────────────
    @track testDate            = '';
    @track firearmInstructor   = '';
    @track location            = '';
    @track lightningCondition  = '';
    @track lcDaytime           = false;
    @track lcNighttime         = false;

    // ── Table ─────────────────────────────────────────────────────────────
    @track isLoadingMembers = false;
    @track tableSearchKey   = '';

    // One row per member shape:
    // { memberId, contactName, contactUrl, tins, division, region,
    //   pistol, pistolYes, pistolNo,
    //   shotgun, shotgunYes, shotgunNo,
    //   rifle, rifleYes, rifleNo,
    //   lightningCondition, lcDaytime, lcNighttime,
    //   qualAttempt, qa1st, qa2nd, qa3rd, qa4th,
    //   isSelected, rowClass }
    @track rowData = [];

    selectedMemberIds = new Set();

    // ── Lifecycle ──────────────────────────────────────────────────────────
    connectedCallback() {
        this.loadRecruitClasses();
    }

    // ── Computed ───────────────────────────────────────────────────────────
    get memberCount()  { return this.rowData.length; }
    get hasSelection() { return this.selectedMemberIds.size > 0; }
    get selectedCount(){ return this.selectedMemberIds.size; }

    get isAddDisabled() {
        return this.selectedMemberIds.size === 0 || !this.testDate;
    }

    get allSelected() {
        return this.rowData.length > 0 &&
               this.rowData.every(r => this.selectedMemberIds.has(r.memberId));
    }

    get filteredRows() {
        if (!this.tableSearchKey || !this.tableSearchKey.trim()) {
            return this.rowData;
        }
        const key = this.tableSearchKey.toLowerCase();
        return this.rowData.filter(r =>
            (r.contactName && r.contactName.toLowerCase().includes(key)) ||
            (r.tins        && r.tins.toLowerCase().includes(key))        ||
            (r.division    && r.division.toLowerCase().includes(key))
        );
    }

    // ── Load Recruit Classes ───────────────────────────────────────────────
    loadRecruitClasses() {
        this.isLoadingClasses = true;
        getRecruitClasses()
            .then(result => {
                this.allRecruitClasses = result;
                this.recruitClasses    = result;
                this.isLoadingClasses  = false;
            })
            .catch(error => {
                this.isLoadingClasses = false;
                this.showErrorToast('Failed to load Recruit Classes: ' + this.reduceErrors(error));
            });
    }

    // ── RC Dropdown ────────────────────────────────────────────────────────
    toggleRcDropdown() {
        this.showRcDropdown = !this.showRcDropdown;
        if (this.showRcDropdown) {
            this.rcSearchKey    = '';
            this.recruitClasses = this.allRecruitClasses;
        }
    }

    handleRcSearch(event) {
        this.rcSearchKey    = event.target.value;
        const key           = this.rcSearchKey.toLowerCase();
        this.recruitClasses = key
            ? this.allRecruitClasses.filter(rc => rc.Name.toLowerCase().includes(key))
            : this.allRecruitClasses;
    }

    handleSelectClass(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.selectedRecruitClass = { Id: id, Name: name };
        this.showRcDropdown       = false;
        this.rcSearchKey          = '';
        this.rowData              = [];
        this.selectedMemberIds    = new Set();
        this.tableSearchKey       = '';
        this.loadMembers(id);
    }

    handleClearClass() {
        this.selectedRecruitClass = null;
        this.rowData              = [];
        this.selectedMemberIds    = new Set();
        this.tableSearchKey       = '';
        this.showRcDropdown       = false;
    }

    // ── Load Members ───────────────────────────────────────────────────────
    loadMembers(recruitClassId) {
        this.isLoadingMembers = true;
        getContactMembers({ recruitClassId })
            .then(members => {
                this.rowData          = members.map(m => this.buildRow(m));
                this.isLoadingMembers = false;
            })
            .catch(error => {
                this.isLoadingMembers = false;
                this.showErrorToast('Failed to load members: ' + this.reduceErrors(error));
            });
    }

    buildRow(m) {
        return {
            memberId    : m.Id,
            contactName : m.Contact__r ? m.Contact__r.Name : '—',
            contactUrl  : m.Contact__c ? `/lightning/r/Contact/${m.Contact__c}/view` : null,
            tins        : m.TINS__c     || '',
            division    : m.Division__c || '',
            region      : m.Region__c   || '',
            // Weapon checkboxes
            pistol      : false,
            shotgun     : false,
            rifle       : false,
            // Selection
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
            rowClass  : this.selectedMemberIds.has(r.memberId) ? 'member-row row-selected' : 'member-row'
        }));
    }

    // ── Weapon checkbox handler ────────────────────────────────────────────
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
                if (typeof e === 'string') return e;
                if (e.message) return e.message;
                if (e.body && e.body.message) return e.body.message;
                return JSON.stringify(e);
            }).join(', ');
        }
        if (errors?.body?.message) return errors.body.message;
        if (errors?.message)       return errors.message;
        return 'Unknown error';
    }
}