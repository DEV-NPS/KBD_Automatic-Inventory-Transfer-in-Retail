tableextension 70007 "NPSRTR Location" extends Location
{
    fields
    {
        field(70000; "NPSRTR Wholesale Location Code"; Code[20])
        {
            Caption = 'Wholesale Location Code';
            DataClassification = CustomerContent;
            TableRelation = Location;
        }
        field(70001; "NPSRTR Reclass Nos."; Code[20])
        {
            Caption = 'Reclass Nos.';
            DataClassification = CustomerContent;
            TableRelation = "No. Series";
        }
    }
}
