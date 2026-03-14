({
    close : function() {
        $A.get("e.force:closeQuickAction").fire();
        var navEvt = $A.get("e.force:navigateToObjectHome");
        navEvt.setParams({
            scope: "Recruit_Class__c"
        });
        navEvt.fire();
    }
})