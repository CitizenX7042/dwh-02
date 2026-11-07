/****** Object:  StoredProcedure [dbo].[CheckObligo]    Script Date: 17/07/2026 17:09:15 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


create       Procedure [dbo].[CheckObligo]
                 @Stockid 	int,   
  						   @res     	int output
-------------------------------------------------------------------*/
/*																																 */
/*																																 */
/* CheckObligo dafna	01/06/2005  																 */
-------------------------------------------------------------------*/
--בדיקה שלא חורגים מקו אובליגו
As
declare @Documentid          int,
        @SalesDoc            int,
  			@AccountKey          varchar(15), 
     		@dev                 float, 
        @OBLIGODELIVERY      int,
			  @st_newObligo        float,
        @ST_MaxObligo        float, 
			  @Balance             float,   
			  @StCurrency          VarChar(5),  
			  @MaxObligoCurrency   VarChar(5),
			  @TO_PAY              float,
			  @rate                float,
			  @ObligoAlarm         int,
        @SumObligo           float,
        @pay                 float,
        @cheq                float,
				@UpdateJurnal        int,
        @MainRate            float,
        @MYERROR 						 int 


set @MYERROR=0
  
select @AccountKey=Accountkey,@Documentid=Documentid,@StCurrency=Currency,@TO_PAY=tftal
from   stock
where stock.id=@Stockid

select @SalesDoc=SalesDoc
from DocumentsDef
where documentid=@Documentid

select @MaxObligoCurrency=MaxObligoCurrency
from accounts
where accountKey=@accountKey

set @MYERROR=@@ERROR

if @SalesDoc<>1
    begin
       set @res=1
       return (@MYERROR)
    end
  
 
select @OBLIGODELIVERY=ObligoDelivery,@ObligoAlarm=ObligoAlarm
from COMPANYDEFENITIONS
--בחשבשבת יש צובר 
exec @MYERROR=invGetObligo     @AccountKey ,@st_newObligo    

if @MYERROR<>0
return @MYERROR
 
exec @MYERROR=InvMaxObligo     @AccountKey ,@ST_MaxObligo  output,@Stockid ,@MaxObligoCurrency
if @MYERROR<>0
return @MYERROR


set @SumObligo=@st_newObligo-@ST_MaxObligo

If @SumObligo<0
    set @SumObligo=0
--  צריך גם לקחת שיקים פתוחים מקבלה
--If( Val({TC___[MAIN][Stock]DocumentID})=2 Or Val({TC___[MAIN][Stock]DocumentID})=62 Or Val({TC___[MAIN][Stock]DocumentID})=87,
--  cheq<<Eadx("Kabala1.hds",CurrentCheqs,{TC___[MAIN][Stock]ID})
--)[;]

select @MainRate=MainRate
from stock
where stock.id=@Stockid
--סה"כ של המסמך לפי מטבע
set @PAY=@TO_PAY*@MainRate


select  @UpdateJurnal=UpdatfJurnal
from documentsdef
where documentid=@documentid

set @cheq=0
--חשבונית מס קבלה
if @DocumentID=2 or @DocumentID=62 or @DocumentID=87
        set @Dev=@ST_NewObligo-@ST_MaxObligo+@cheq
     else
        set @Dev=@ST_NewObligo-@ST_MaxObligo+@PAY*@UpdateJurnal
    
--ההודעה היא בהתאם להרשאה של המשתמש
If @ObligoAlarm=0 And @Dev>0
    begin
       set @res=1
       return (@MYERROR)
    end


/*
--------------בעיה גם הודעה למסך
If( Val({TC___[MAIN][COMPANYDEFENITIONS]ObligoAlarm})=1 And Val(Dev)>0,
        Mes<< MessageBox("חריגה מאובליגו האם להמשיך בהפקה",5,2),
         If(StrCmp(Mes,"YES")=1,
            Return(1),
          else,         
           Return(0)
          )  
)[;]
If( Val({TC___[MAIN][COMPANYDEFENITIONS]ObligoAlarm})=2 And Val(Dev)>0,
        If (Val(Eadx("users.hds","CanConfirmDeviations"))=1,
            Mes<< MessageBox("חריגה מאובליגו האם להמשיך בהפקה",5,2),
                         If(StrCmp(Mes,"YES")=1,
                              Return(1),
                          else,         
                               Return(0)
                             )  
            ),
          MessageBox("חריגה מאובליגו",2),
           Return(0)
)[;]
*/
set @res=1
return (@MYERROR)






GO
