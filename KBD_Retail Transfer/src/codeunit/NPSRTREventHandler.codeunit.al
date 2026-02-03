codeunit 70006 "NPSRTR Event Handler"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnPostItemJnlLineOnAfterPrepareItemJnlLine, '', false, false)]
    local procedure OnPostItemJnlLineOnAfterPrepareItemJnlLineRetail(var ItemJournalLine: Record "Item Journal Line"; SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header"; WhseShip: Boolean; var ItemJnlPostLine: Codeunit "Item Jnl.-Post Line"; var QtyToBeShipped: Decimal; TrackingSpecification: Record "Tracking Specification"; var QtyToBeInvoiced: Decimal; var QtyToBeInvoicedBase: Decimal; var QtyToBeShippedBase: Decimal; var RemAmt: Decimal; var RemDiscAmt: Decimal)
    var
        Location: Record Location;
        Currency: Record Currency;
    begin
        IF SalesHeader."Currency Code" = '' THEN
            Currency.InitRoundingPrecision
        ELSE BEGIN
            Currency.GET(SalesHeader."Currency Code");
            Currency.TESTFIELD("Amount Rounding Precision");
        END;
        IF (SalesLine."Document Type" = SalesLine."Document Type"::Order) AND (SalesLine.Quantity > 0) THEN
            ItemReclas(ItemJnlPostLine, SalesHeader, SalesLine, ItemJournalLine."Source Code", TrackingSpecification);

        //IF (SalesLine."Document Type" IN [SalesLine."Document Type"::"Return Order", SalesLine."Document Type"::"Credit Memo"]) THEN
        //    ItemReclasCrMemo(ItemJnlPostLine, SalesHeader, SalesLine, ItemJournalLine."Source Code", TrackingSpecification);

    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnAfterPostItemJnlLine, '', false, false)]
    local procedure OnAfterPostItemJnlLineRetail(var ItemJournalLine: Record "Item Journal Line"; SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header"; WhseShip: Boolean; var ItemJnlPostLine: Codeunit "Item Jnl.-Post Line"; var TempHandlingSpecification: Record "Tracking Specification"; var ItemShptEntryNo: Integer)
    var
        Location: Record Location;
        Currency: Record Currency;
    begin
        IF SalesHeader."Currency Code" = '' THEN
            Currency.InitRoundingPrecision
        ELSE BEGIN
            Currency.GET(SalesHeader."Currency Code");
            Currency.TESTFIELD("Amount Rounding Precision");
        END;

        IF (SalesLine."Document Type" IN [SalesLine."Document Type"::"Return Order", SalesLine."Document Type"::"Credit Memo"]) THEN
            ItemReclasCrMemo(ItemJnlPostLine, SalesHeader, SalesLine, ItemJournalLine."Source Code", TempHandlingSpecification, ItemShptEntryNo);

    end;


    local procedure ItemReclas(var ItemJnlPostLine: Codeunit "Item Jnl.-Post Line"; SalesHeader: Record "Sales Header"; SalesLine: Record "Sales Line"; SourceCode: Code[20]; TrackingSpec: Record "Tracking Specification")
    var
        Location: Record Location;
        Item: Record Item;
        ItemJnlLine: Record "Item Journal Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        ReservationEntry: Record "Reservation Entry";
        ReservationEntry2: Record "Reservation Entry";
        LotNoInfo: Record "Lot No. Information";
        EntryNo: Integer;
        QtyToShip: Decimal;
        Qty: Decimal;
    begin
        IF (SalesLine.Type <> SalesLine.Type::Item) THEN
            EXIT;
        Location.GET(SalesLine."Location Code");
        IF NOT Location."NPSSPI Retail Location" THEN
            EXIT;
        Item.GET(SalesLine."No.");
        ReservationEntry2.SetCurrentKey("Item No.", "Reservation Status", "Source Type", "Source Subtype", "Source ID", "Source Ref. No.");
        ReservationEntry2.SetRange("Item No.", SalesLine."No.");
        ReservationEntry2.SetFilter("Reservation Status", '<>%1', ReservationEntry2."Reservation Status"::Prospect);
        ReservationEntry2.SetRange("Source Type", Database::"Sales Line");
        ReservationEntry2.SetRange("Source Subtype", 1);
        ReservationEntry2.SetRange("Source ID", SalesHeader."No.");
        ReservationEntry2.SetRange("Source Ref. No.", SalesLine."Line No.");
        ReservationEntry2.SetFilter("Item Tracking", '<>%1', ReservationEntry2."Item Tracking"::None);
        IF ReservationEntry2.FINDSET THEN
            REPEAT
                ReservationEntry.RESET;
                IF ReservationEntry.FINDLAST THEN
                    EntryNo := ReservationEntry."Entry No.";
                ItemJnlLine.INIT;
                FillItemJnlLine(ItemJnlLine, SalesHeader, SalesLine, Item."Inventory Posting Group", Location."NPSRTR Reclass Nos.", SourceCode, Item."Base Unit of Measure", SalesHeader."Shipping No.");
                ItemJnlLine.VALIDATE(Quantity, ABS(ReservationEntry2."Quantity (Base)"));
                ItemJnlLine.VALIDATE("Invoiced Quantity", ItemJnlLine.Quantity);
                ItemJnlLine.VALIDATE("Quantity (Base)", ItemJnlLine.Quantity);
                ItemJnlLine.VALIDATE("Invoiced Qty. (Base)", ItemJnlLine.Quantity);
                ItemJnlLine."New Location Code" := SalesLine."Location Code";
                IF Location."NPSRTR Wholesale Location Code" <> '' THEN
                    ItemJnlLine."Location Code" := Location."NPSRTR Wholesale Location Code"
                ELSE
                    ItemJnlLine."Location Code" := GetLocCodeFromTracking(SalesLine."No.", ReservationEntry2."Lot No.");
                ItemJnlLine."Expiration Date" := ReservationEntry2."Expiration Date";
                ItemJnlLine."New Item Expiration Date" := ReservationEntry2."Expiration Date";
                ReservationEntry.INIT;
                ReservationEntry."Entry No." := EntryNo + 1;
                ReservationEntry.INSERT;
                ReservationEntry."Reservation Status" := ReservationEntry."Reservation Status"::Prospect;
                ReservationEntry."Creation Date" := WORKDATE;
                ReservationEntry."Source Type" := DATABASE::"Item Journal Line";
                ReservationEntry."Source Subtype" := ItemJnlLine."Entry Type"::Transfer;
                ReservationEntry."Source ID" := '';
                ReservationEntry."Source Ref. No." := ItemJnlLine."Line No.";
                ReservationEntry.VALIDATE("Location Code", ItemJnlLine."Location Code");
                ReservationEntry.VALIDATE("Item No.", ItemJnlLine."Item No.");
                ReservationEntry.VALIDATE("Quantity (Base)", -ItemJnlLine.Quantity);
                ReservationEntry.VALIDATE("Qty. to Handle (Base)", -ItemJnlLine.Quantity);
                ReservationEntry.VALIDATE(Quantity, -ItemJnlLine.Quantity);
                ReservationEntry."Item Tracking" := ReservationEntry."Item Tracking"::"Lot No.";
                ReservationEntry."Lot No." := ReservationEntry2."Lot No.";
                ReservationEntry."New Lot No." := ReservationEntry2."Lot No.";
                if LotNoInfo.Get(ReservationEntry2."Item No.", ReservationEntry2."Variant Code", ReservationEntry2."Lot No.") then begin
                    ReservationEntry."Expiration Date" := LotNoInfo."NPSKBD Expiration Date";
                    ReservationEntry."New Expiration Date" := LotNoInfo."NPSKBD Expiration Date";
                end;
                ReservationEntry.MODIFY;
                ItemJnlPostLine.RunWithCheck(ItemJnlLine);
            UNTIL ReservationEntry2.NEXT = 0
        ELSE BEGIN
            ItemLedgerEntry.SETCURRENTKEY("Item No.", Open, "Variant Code", Positive, "Location Code");
            ItemLedgerEntry.SETRANGE("Item No.", SalesLine."No.");
            ItemLedgerEntry.SETRANGE(Open, TRUE);
            ItemLedgerEntry.SETRANGE("Variant Code", SalesLine."Variant Code");
            ItemLedgerEntry.SETRANGE(Positive, TRUE);
            ItemLedgerEntry.SETRANGE("Location Code", SalesLine."Location Code");
            ItemLedgerEntry.CALCSUMS("Remaining Quantity");
            QtyToShip := ItemLedgerEntry."Remaining Quantity";
            IF QtyToShip >= -SalesLine."Qty. to Ship (Base)" THEN
                EXIT;
            Location.TESTFIELD("NPSRTR Reclass Nos.");
            SalesLine.TESTFIELD("Bin Code", '');
            IF Location."NPSRTR Wholesale Location Code" <> '' THEN
                ItemLedgerEntry.SETRANGE("Location Code", Location."NPSRTR Wholesale Location Code")
            ELSE
                ItemLedgerEntry.SETFILTER("Location Code", '<>%1', SalesLine."Location Code");
            IF ItemLedgerEntry.FINDFIRST THEN
                REPEAT
                    ItemJnlLine.INIT;
                    FillItemJnlLine(ItemJnlLine, SalesHeader, SalesLine, Item."Inventory Posting Group", Location."NPSRTR Reclass Nos.", SourceCode, Item."Base Unit of Measure", SalesHeader."Shipping No.");
                    ItemJnlLine."Location Code" := ItemLedgerEntry."Location Code";
                    Qty := -SalesLine."Qty. to Ship (Base)" - QtyToShip;
                    IF Qty > ItemLedgerEntry.Quantity THEN BEGIN
                        ItemJnlLine.Quantity := ItemLedgerEntry.Quantity;
                        QtyToShip += ItemLedgerEntry.Quantity;
                    END ELSE BEGIN
                        ItemJnlLine.Quantity := Qty;
                        QtyToShip += Qty;
                    END;
                    ItemJnlLine."New Location Code" := SalesLine."Location Code";
                    ItemJnlLine."Invoiced Quantity" := ItemJnlLine.Quantity;
                    ItemJnlLine."Quantity (Base)" := ItemJnlLine.Quantity;
                    ItemJnlLine."Invoiced Qty. (Base)" := ItemJnlLine.Quantity;
                    ItemJnlPostLine.RunWithCheck(ItemJnlLine);
                UNTIL (ItemLedgerEntry.NEXT = 0) OR (QtyToShip = -SalesLine."Qty. to Ship (Base)");
        END;
    end;

    local procedure ItemReclasCrMemo(VAR ItemJnlPostLine: Codeunit "Item Jnl.-Post Line"; SalesHeader: Record "Sales Header"; SalesLine: Record "Sales Line"; SourceCode: Code[20]; var TrackingSpec: Record "Tracking Specification" temporary; ItemShptEntryNo: Integer)
    var
        LocationLoc: Record Location;
        ItemLoc: Record Item;
        ItemJnlLine: Record "Item Journal Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        ValueEntry: Record "Value Entry";
        ILE: Record "Item Ledger Entry";
        ReservationEntry: Record "Reservation Entry";
        ReservationEntry2: Record "Reservation Entry";
        ExtDocNo: Code[20];
        LastEntry: Integer;
        EntryNo: Integer;
        QtyToShip: Decimal;
    begin
        IF (SalesLine.Type <> SalesLine.Type::Item) THEN
            EXIT;
        LocationLoc.GET(SalesLine."Location Code");
        IF NOT LocationLoc."NPSSPI Retail Location" THEN
            EXIT;
        LocationLoc.TESTFIELD("NPSRTR Reclass Nos.");
        SalesLine.TESTFIELD("Bin Code", '');

        ValueEntry.SETRANGE("Document Type", ValueEntry."Document Type"::"Sales Invoice");
        ValueEntry.SETRANGE("Document No.", SalesHeader."Applies-to Doc. No.");
        IF ValueEntry.FINDFIRST THEN
            ILE.GET(ValueEntry."Item Ledger Entry No.");
        ExtDocNo := ILE."Document No.";
        QtyToShip := ILE.Quantity;

        IF ItemLedgerEntry.FINDLAST THEN BEGIN
            LastEntry := ItemLedgerEntry."Entry No.";
            QtyToShip := ItemLedgerEntry.Quantity;
        END ELSE
            EXIT;

        IF TrackingSpec.FINDSET THEN
            REPEAT
                ReservationEntry.RESET;
                IF ReservationEntry.FINDLAST THEN
                    EntryNo := ReservationEntry."Entry No.";
                ItemJnlLine.INIT;
                FillItemJnlLine(ItemJnlLine, SalesHeader, SalesLine, ItemLoc."Inventory Posting Group", LocationLoc."NPSRTR Reclass Nos.", SourceCode, ItemLoc."Base Unit of Measure", ExtDocNo);
                ItemJnlLine."Location Code" := SalesLine."Location Code";
                IF LocationLoc."NPSRTR Wholesale Location Code" <> '' THEN
                    ItemJnlLine."New Location Code" := LocationLoc."NPSRTR Wholesale Location Code"
                ELSE
                    ItemJnlLine."New Location Code" := GetLocCodeFromTracking(SalesLine."No.", TrackingSpec."Lot No.");
                ItemJnlLine.Quantity := TrackingSpec."Quantity (Base)";
                ItemJnlLine."Invoiced Quantity" := ItemJnlLine.Quantity;
                ItemJnlLine."Quantity (Base)" := ItemJnlLine.Quantity;
                ItemJnlLine."Invoiced Qty. (Base)" := ItemJnlLine.Quantity;
                ItemJnlLine."Applies-to Entry" := TrackingSpec."Item Ledger Entry No.";
                ReservationEntry.INIT;
                ReservationEntry."Entry No." := EntryNo + 1;
                ReservationEntry.INSERT;
                ReservationEntry."Reservation Status" := ReservationEntry."Reservation Status"::Prospect;
                ReservationEntry."Creation Date" := WORKDATE;
                ReservationEntry."Source Type" := DATABASE::"Item Journal Line";
                ReservationEntry."Source Subtype" := ItemJnlLine."Entry Type"::Transfer;
                ReservationEntry."Source ID" := '';
                ReservationEntry."Source Ref. No." := ItemJnlLine."Line No.";
                IF LocationLoc."NPSRTR Wholesale Location Code" <> '' THEN
                    ReservationEntry.Validate("Location Code", LocationLoc."NPSRTR Wholesale Location Code")
                ELSE
                    ReservationEntry.Validate("Location Code", GetLocCodeFromTracking(SalesLine."No.", TrackingSpec."Lot No."));
                ReservationEntry.VALIDATE("Item No.", ItemJnlLine."Item No.");
                ReservationEntry.Validate("Appl.-to Item Entry", TrackingSpec."Item Ledger Entry No.");
                ReservationEntry.VALIDATE("Quantity (Base)", -ItemJnlLine.Quantity);
                ReservationEntry.VALIDATE("Qty. to Handle (Base)", -ItemJnlLine.Quantity);
                ReservationEntry.VALIDATE(Quantity, -ItemJnlLine.Quantity);
                ReservationEntry."Item Tracking" := ReservationEntry."Item Tracking"::"Lot No.";
                ReservationEntry."Lot No." := TrackingSpec."Lot No.";
                ReservationEntry."New Lot No." := TrackingSpec."Lot No.";
                ReservationEntry."Expiration Date" := TrackingSpec."Expiration Date";
                ReservationEntry."New Expiration Date" := TrackingSpec."Expiration Date";
                ReservationEntry.MODIFY;

                ItemJnlPostLine.RunWithCheck(ItemJnlLine);
            UNTIL TrackingSpec.NEXT = 0
        ELSE BEGIN
            ILE.SETRANGE("Entry Type", ILE."Entry Type"::Transfer);
            ILE.SETRANGE("External Document No.", ExtDocNo);
            IF LocationLoc."NPSRTR Wholesale Location Code" <> '' THEN
                ILE.SETRANGE("Location Code", LocationLoc."NPSRTR Wholesale Location Code")
            ELSE
                ILE.SETFILTER("Location Code", '<>%1', SalesLine."Location Code");
            ILE.SETRANGE(Open, FALSE);
            ILE.SETRANGE(Positive, FALSE);
            ILE.SETFILTER("Entry No.", '<=%1', LastEntry);
            IF ILE.FINDSET THEN
                REPEAT
                    ItemJnlLine.INIT;
                    FillItemJnlLine(ItemJnlLine, SalesHeader, SalesLine, ItemLoc."Inventory Posting Group", LocationLoc."NPSRTR Reclass Nos.", SourceCode, ItemLoc."Base Unit of Measure", ExtDocNo);
                    ItemJnlLine."Location Code" := SalesLine."Location Code";
                    ItemJnlLine."New Location Code" := ILE."Location Code";
                    ItemJnlLine."Lot No." := ILE."Lot No.";
                    ItemJnlLine."New Lot No." := ILE."Lot No.";
                    IF (QtyToShip + ILE.Quantity) > 0 THEN
                        ItemJnlLine.Quantity := -ILE.Quantity
                    ELSE
                        ItemJnlLine.Quantity := -QtyToShip;
                    QtyToShip -= ItemJnlLine.Quantity;
                    ItemJnlLine."Invoiced Quantity" := ItemJnlLine.Quantity;
                    ItemJnlLine."Quantity (Base)" := ItemJnlLine.Quantity;
                    ItemJnlLine."Invoiced Qty. (Base)" := ItemJnlLine.Quantity;
                    ItemJnlPostLine.RunWithCheck(ItemJnlLine);
                UNTIL (ILE.NEXT = 0) OR (QtyToShip <= 0);
        END;
    end;

    local procedure FillItemJnlLine(var ItemJnlLine: Record "Item Journal Line"; SalesHeader: Record "Sales Header"; SalesLine: Record "Sales Line"; InventoryPostingGroup: Code[20]; ReclassNos: Code[20]; SourceCode: Code[20]; BaseUOM: Code[20]; ExtDocNo: Code[20])
    var
        NoSeriesMgt: Codeunit "No. Series";
        Qty: Decimal;
    begin
        ItemJnlLine."Posting Date" := SalesHeader."Posting Date";
        ItemJnlLine."Document Date" := SalesHeader."Document Date";
        ItemJnlLine."Item No." := SalesLine."No.";
        ItemJnlLine.Description := SalesLine.Description;
        ItemJnlLine."Gen. Prod. Posting Group" := SalesLine."Gen. Prod. Posting Group";
        ItemJnlLine."Gen. Bus. Posting Group" := SalesLine."Gen. Bus. Posting Group";
        ItemJnlLine."Inventory Posting Group" := InventoryPostingGroup;
        ItemJnlLine."Variant Code" := SalesLine."Variant Code";
        ItemJnlLine."Country/Region Code" := SalesHeader."Sell-to Country/Region Code";
        ItemJnlLine."Transaction Type" := SalesHeader."Transaction Type";
        ItemJnlLine."Transport Method" := SalesHeader."Transport Method";
        ItemJnlLine."Entry/Exit Point" := SalesHeader."Exit Point";
        ItemJnlLine.Area := SalesHeader.Area;
        ItemJnlLine."Transaction Specification" := SalesHeader."Transaction Specification";
        //ItemJnlLine."Product Group Code" := SalesLine."Product Group Code"; TODO
        ItemJnlLine."Item Category Code" := SalesLine."Item Category Code";
        ItemJnlLine."Document No." := NoSeriesMgt.GetNextNo(ReclassNos, SalesLine."Posting Date", TRUE);
        ItemJnlLine."Posting No. Series" := ReclassNos;
        ItemJnlLine."External Document No." := ExtDocNo;
        ItemJnlLine."Entry Type" := ItemJnlLine."Entry Type"::Transfer;
        ItemJnlLine."Shortcut Dimension 1 Code" := SalesLine."Shortcut Dimension 1 Code";
        ItemJnlLine."New Shortcut Dimension 1 Code" := SalesLine."Shortcut Dimension 1 Code";
        ItemJnlLine."Shortcut Dimension 2 Code" := SalesLine."Shortcut Dimension 2 Code";
        ItemJnlLine."New Shortcut Dimension 2 Code" := SalesLine."Shortcut Dimension 2 Code";
        ItemJnlLine."Dimension Set ID" := SalesLine."Dimension Set ID";
        ItemJnlLine."New Dimension Set ID" := SalesLine."Dimension Set ID";
        ItemJnlLine."Source Code" := SourceCode;
        ItemJnlLine."Unit of Measure Code" := BaseUOM;
        ItemJnlLine."Qty. per Unit of Measure" := 1;
        ItemJnlLine."Source Type" := ItemJnlLine."Source Type"::Customer;
        ItemJnlLine."Source No." := SalesHeader."Sell-to Customer No.";
    end;

    local procedure GetLocCodeFromTracking(ItemNo: Code[20]; LotNo: Code[20]): Code[20]
    var
        ItemLedgEntry: Record "Item Ledger Entry";
    begin
        ItemLedgEntry.SetRange("Item No.", ItemNo);
        ItemLedgEntry.SetRange("Lot No.", LotNo);
        ItemLedgEntry.SetRange(Open, true);
        if ItemLedgEntry.FindFirst() then
            exit(ItemLedgEntry."Location Code")
        else
            exit('');
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Tracking Data Collection", OnRetrieveLookupDataOnAfterReservEntrySetFilters, '', false, false)]
    local procedure OnRetrieveLookupDataOnAfterReservEntrySetFiltersRetail(var ReservEntry: Record "Reservation Entry"; TempTrackingSpecification: Record "Tracking Specification" temporary)
    var
        Location: Record Location;
    begin
        IF (Location.GET(TempTrackingSpecification."Location Code")) AND (Location."NPSSPI Retail Location") THEN
            IF Location."NPSRTR Wholesale Location Code" <> '' THEN
                ReservEntry.SETRANGE("Location Code", Location."NPSRTR Wholesale Location Code")
            ELSE
                ReservEntry.SETFILTER("Location Code", '<>%1', Location.Code);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Tracking Data Collection", OnRetrieveLookupDataOnBeforeTransferToTempRec, '', false, false)]
    local procedure OnRetrieveLookupDataOnBeforeTransferToTempRecRetail(var TempTrackingSpecification: Record "Tracking Specification" temporary; var TempReservationEntry: Record "Reservation Entry" temporary; var ItemLedgerEntry: Record "Item Ledger Entry"; var FullDataSet: Boolean)
    var
        Location: Record Location;
    begin
        IF (Location.GET(TempTrackingSpecification."Location Code")) AND (Location."NPSSPI Retail Location") THEN
            IF Location."NPSRTR Wholesale Location Code" <> '' THEN
                ItemLedgerEntry.SETRANGE("Location Code", Location."NPSRTR Wholesale Location Code")
            ELSE
                ItemLedgerEntry.SETFILTER("Location Code", '<>%1', Location.Code);
    end;
}
