/****** Object:  StoredProcedure [dbo].[ChBeforIssue]    Script Date: 17/07/2026 17:09:15 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 
create            Procedure [dbo].[ChBeforIssue]
                 @STOCKID  int,
                 @res      int output 
/*-----------------------------------------------------------------*/
/*																																 */
/*																																 */
/* (EX)ChBeforIssue dafna				12/06/2005												 */
/*-----------------------------------------------------------------*/
--בדיקות לפני הפקה   
As

set nocount on
declare @TaxYearLow  		datetime,
        @TaxYearHigh 		datetime,
        @MYERROR  			int,
        @ErrorFrom  		int,
        @UpdateJurnal 	int,
        @VatTransType   varchar(3),
        @PurchBudget    int,
        @SaleBudget     int,
        @stockValue     datetime,
				@Copies					int,
        @documentid     int, 
        @Fix            int,
        @tftal					int,
        @stockupdate		int,    
				@tftalvat				float,
				@tftalvatfree		float


        
set @MYERROR=0           

select @TaxYearLow=TaxYearLow,@TaxYearHigh=TaxYearHigh,@PurchBudget=PurchBudget,@SaleBudget=SaleBudget
from CompanyDefenitions

select @stockValue=Valuedate,@Copies=Copies
from stock
where stock.id=@stockid


select @documentid=documentid
from stock
where id=@stockid

select @fix=FixNumerator,@stockUpdate=stockUpdate
from documentsdef
where documentid=@documentid


-----------
--(vad)Copies
--בקבוע צריך עותק אחד לפחות
if @fix<>0 and  @Copies=0
begin 

    exec @MYERROR=InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.Copy',75,2   
    goto END_HANDLER_0
end
----------------

if @stockValue<@TaxYearLow or @stockValue>@TaxYearHigh
begin

    exec @MYERROR=InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.ValueDate',53,2   
    goto END_HANDLER_0
end

--שונה בחשבשבת    
if datediff(day,@stockValue,getdate())<>0
begin

    exec InvUpdateErrorMessage @STOCKID,@STOCKID,1,'Stock.ValueDate',74,2   
--    set @MYERROR=@@ERROR
--    goto END_HANDLER_0
end

set @res=0
--בדיקת אשראי
exec @MYERROR=ChCredit    @Stockid,@Res output    

if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end

--בדיקות תקינות לפני הפקה
exec  @MYERROR=CheckObligo  @Stockid , @res output

if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end
--בדיקת מספרים טבועים
exec @MYERROR=InvChZelemsInDoc @StockID , @res output 

if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end
--בדיקת מונה
exec @MYERROR=CheckCounterInDoc   @StockID,@res output 

if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end
--בדיקת חשבון בשורת פריט
exec @MYERROR=InvCheckItemsIncomeAct   @Stockid ,@res output    

if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end

exec @MYERROR=InvIsDocNoExist  @stockid ,0,@res output  

if  @Res<>0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end


select @documentID=documentID,@VatTransType=TRANSTYPE,@tftal=tftal ,@tftalvat=tftalvat, @tftalvatfree=tftalvatfree 
from stock
where stock.id=@stockid

select @UpdateJurnal=UpdatfJurnal
from DocumentsDef
where DocumentID=@DocumentID
--בדיקת פיצול תשלומים

if @UpdateJurnal!=0
 if (select sum(SharePrc)
     from DefaultsStockJurnalDetails
     where stockid=@stockid)<>100
         begin
			     --rollback tran
     			 exec InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.ID',67,2  
   			   goto END_HANDLER_0
   end
set @res=0



--בדיקת סוג תנועה חייב במעמ
if @tftalvat <>0 and @UpdateJurnal<>0
    begin
		  exec @MYERROR=IntChVatTransType @StockId,@documentid, @VatTransType ,@res output 
  		if @res=0 or @MYERROR<>0
        goto END_HANDLER_0
    	end 
 --בדיקת סוג תנועה פטור ממעמ   
if @tftalvatfree <>0 and @UpdateJurnal<>0
    begin
		  exec @MYERROR=IntChVatFreeTransType @StockId,@documentid, @VatTransType ,@res output 
  		if @res=0  or @MYERROR<>0
          goto END_HANDLER_0
   	end 

if @tftal=0 and @UpdateJurnal<>0
	  begin
  			exec InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.ID',68,2   
   			goto END_HANDLER_0
  	end 
--חשבונית עצמית
 If  @DocumentID=88
 			begin

  				exec @MYERROR=Inv_stock_trans_inv @STOCKID,@documentid,@VatTransType,@res
          if  @res=0 or @MYERROR<>0
            goto END_HANDLER_0
			end


If  @tftal = 0 And @UpdateJurnal != 0
begin
       --rollback tran
				exec InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.ID',86,2   
   			goto END_HANDLER_0
end 

exec @MYERROR=prInvCustExtraCheck  @stockid ,@res  OUTPUT

if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end
--בדיקת שער
exec @MYERROR=prInvCheckRate  @stockid ,@res  OUTPUT

if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end
 
 

--תקציב רכש
If @PurchBudget>0
begin
 exec @MYERROR=prInvChkBudget  @stockid ,@res  OUTPUT
 if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end
end
 
If @SaleBudget>0
begin
 exec @MYERROR=prChkBudgetSell  @stockid ,@res  OUTPUT
 if  @Res=0 or @MYERROR<>0
    begin
      goto END_HANDLER_0
 end

end

declare @RptNum int
--פורמט הדפסה
select @RptNum=PrintStyle
from stock
where stock.id=@stockid

if (select count(*)
from wizcomp..RptDocs
where RptNum=@RptNum)=0
begin
      --rollback tran
			exec @MYERROR=InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.ID',87,2   
      goto END_HANDLER_0
end

--בדיקת נכונות סה"כ בשורה
if (select count(*)
from ICHTFTALLINE
where ID=@StockID)>0
begin
      --rollback tran
			exec InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.ID',88,2   
      goto END_HANDLER_0
end

declare  @RptType 			int
--בדיקת פורמט הדפסה בהתאם לסוג מסמך				
select @RptType=RptType
from wizcomp..RptDocs
where RptNum=2

if @UpdateJurnal<>0 and (@RptType<>100 and @RptType<>103 and @RptType<>104)
begin
      --rollback tran
			exec InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.ID',89,2   
      goto END_HANDLER_0
end
else
begin
      goto END_HANDLER_1
end


if @StockUpdate<>0 and (@RptType<>101 and @RptType<>103)
begin
      --rollback tran
			exec InvUpdateErrorMessage @STOCKID,@STOCKID,0,'Stock.ID',89,2   
      goto END_HANDLER_0
end
else
begin
      goto END_HANDLER_1
end


goto END_HANDLER_1

END_HANDLER_0:
if @MYERROR<>0
 goto ERR_HANDLER
else
 begin
  set @res=0
  Return @MYERROR
end

END_HANDLER_1:
if @MYERROR<>0
 goto ERR_HANDLER
else
 begin
  set @res=1
  Return @MYERROR
end

ERR_HANDLER:
if @MYERROR<>0
 begin
       RAISERROR ('PROCEDURE ChBeforIssue:, ERROR %d ', 19, 1,@MYERROR) WITH LOG
       RETURN @MYERROR  
 end




GO
