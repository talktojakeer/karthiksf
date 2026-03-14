import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRecruitClasses from '@salesforce/apex/recruitClassController.getRecruitClasses';
import { refreshApex } from '@salesforce/apex';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';


export default class RecruitClassTab extends NavigationMixin(LightningElement) {
    /*connectedCallback() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Account',
                actionName: 'list'
            }
        });
    }*/
   @track showModal = false;
    wiredResult;
    records = [];

    columns = [
        { label: 'Recruit Class', 
            fieldName: 'recordLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'Name' },  // show Name as text
                target: '_self'                // open in same tab
            },
            cellAttributes: { alignment: 'left' },
            initialWidth: undefined  // let it stretch
        }
    ];

    @wire(getRecruitClasses)
    wiredData(result) {
        this.wiredResult = result; 
        const { data, error } = result;
        if (data) {
            console.log('Data '+JSON.stringify(data));
            this.prepareRecords(data);
        } else if (error) {
            console.error(error);
        }
    }    

    prepareRecords(data) {
        const baseUrl = window.location.origin; 

        this.records = data.map(row => {
            return {
                ...row,
                recordLink: `${baseUrl}/lightning/r/Account/${row.Id}/view`
            };
        });      
    }

    handleRowAction(event){
        const actionValue = event.detail.value;
        const recordId = event.target.dataset.id;
        const recordName = event.target.dataset.name;
        if (actionValue === 'edit') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    actionName: 'edit'
                }
            });

        }else if (actionValue === 'delete') {
            console.log('recordId '+recordId)
            console.log('recordName '+recordName)
            deleteRecord(recordId)
            .then(() => {
                console.log('Deleted');
                refreshApex(this.wiredResult);
            })
            .catch(error => {
                console.error(error);
            });
        }
    }


    openModal() {
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
    }

    handleSuccess() {
        this.showModal = false;
        this.refreshTable();
    }

    refreshTable() {
        refreshApex(this.wiredResult);
    }
}