pageextension 70010 "NPSRTR Location Card" extends "Location Card"
{
    layout
    {
        addlast("NPSSPI Retail")
        {
            field("NPSKBD Reclass Nos."; Rec."NPSRTR Reclass Nos.")
            {
                ApplicationArea = All;
            }
            field("NPSKBD Wholesale Location Code"; Rec."NPSRTR Wholesale Location Code")
            {
                ApplicationArea = All;
            }
        }

    }
}