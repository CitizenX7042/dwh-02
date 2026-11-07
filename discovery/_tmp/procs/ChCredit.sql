/****** Object:  StoredProcedure [dbo].[ChCredit]    Script Date: 17/07/2026 17:09:15 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 

create     Procedure [dbo].[ChCredit]
								@Stockid int,
								@Res     int output 
---------------------------------------------------------------------------*/
/*																																				 */
/*																																				 */
/* ChCredit dafn 29/06/2005																								 */
---------------------------------------------------------------------------
--בודקים שאין חריגה מקו אשראי

As
declare @SalesDoc           int,
        @UpdateJurnal       int,
			  @DocumentID         int,
			  @MaxRate            int,
			  @MaxCreditCurrency  varchar(5),
			  @MainCurrency       varchar(5),
			  @MaxCredit          float,
			  @AccountKey         varchar(15),
			  @CreditAlarm        int,  
        @MYERROR            int    

set @MYERROR=0select @DocumentID=DocumentID
from stock
where id=@Stockid

select @SalesDoc=SalesDoc,@UpdateJurnal=UpdatFJurnal
from DocumentsDef
where DocumentID=@DocumentID


set @MYERROR=@@ERROR

if @SalesDoc=0
   begin
      set @Res=1
      return @MYERROR 
   end 
if @UpdateJurnal=0
   begin
      set @Res=1
   return @MYERROR
   end 
if @DocumentID=2 or @DocumentID=62
   begin
      set @Res=1
   return @MYERROR 
   end 
           
set @MaxRate=1

select @AccountKey=AccountKey
from stock
where stock.id=@Stockid

select @MaxCreditCurrency=MaxCreditCurrency
from accounts
where AccountKey=@AccountKey

select @MainCurrency=MainCurrency,@CreditAlarm=CreditAlarm
from CompanyDefenitions
--משערכים למטבע אשראי
if @MaxCreditCurrency<>@MainCurrency
    begin
       exec @MYERROR=InvGetRate   @MaxCreditCurrency ,NULL,  @MaxRate output
	     if @MaxRate=0
       begin
   	  	  set @Res=1
    	  	return @MYERROR
		   end
        
   		select @MaxCredit=MaxCredit*@MaxRate
   		from accounts a
   		where a.accountkey=@AccountKey
   end

declare @Dev float

select  @Dev=MaxCredit*@MaxRate+Balance-tftal*stock.mainrate
from accounts, stock
where stock.id=@Stockid
and   stock.accountkey=accounts.accountkey
--מתייחסים לסוג ההרשאה של המשתמש
if @CreditAlarm=0 and @Dev<0
begin
   set @Res=1
   return @MYERROR
end

-------בעיה עם משתמשים ועם הודעה למסך
/*
If(Val({TC___[MAIN][COMPANYDEFENITIONS]CreditAlarm})=1 And Val(Dev)<0,  
         Mes<< MessageBox("חריגה מקו אשראי האם להמשיך בהפקה",3),
         If(StrCmp(Mes,"OK")=1,
            Return(1),
          else,         
           Return(0)
          )  
)[;]
If( Val({TC___[MAIN][COMPANYDEFENITIONS]CreditAlarm})=2 And Val(Dev)<0,
         If(Val(Eadx("users.hds","CanConfirmDeviations"))=1,
                                  Mes<< MessageBox("חריגה מקו אשראי האם להמשיך בהפקה",3),
                                  If(StrCmp(Mes,"OK")=1,
                                       Return(1),
                                   else,         
                                        Return(0)
                                     ) 
            ),  
         MessageBox("חריגה מקו אשראי",2),
         Return(0)
             
)[;]
Return(1)[;]
*/


SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN
    	set @res=0   
		 	RAISERROR ('PROCEDURE ChCredit: 1, ERROR %d ', 19, 1,@MYERROR) WITH LOG
 			return @MYERROR
  END
set @res=1
return @MYERROR





GO
