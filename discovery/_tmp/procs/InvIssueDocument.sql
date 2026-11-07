/****** Object:  StoredProcedure [dbo].[InvIssueDocument]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 


create           Procedure [dbo].[InvIssueDocument]
                 @STOCKID  int,
                 @res      int=0 output 
As
/*-----------------------------------------------------------------*/
/*																																 */
/*																																 */
/* InvIssueDocument dafna				13/06/2005		      							 */
/*-----------------------------------------------------------------*/

--מכינים את ההפקה
declare @MYERROR    					int,
			  @SalesDoc    					int,
  			@documentid    				int,
  			@UpdatFJurnal   			int,
  			@Vat     							float, 
  			@ExportDoc            int,
  			@Acc                  varchar(15),  
  			@RESULT               int,
  			@MYTRANCOUNT          INT,
        @IssueJurnalImport    int, 
        @stockTotal           float,
        @DocTotal             float 


set @MYERROR=0
if (select count(*) from intererrmesg
where headerid=@STOCKID
and tbl=1
and err<>1)>0
begin
     return 0			
end


delete from intererrmesg
where headerid=@STOCKID
and tbl=2

set @stockTotal=0 

select @Acc=accountkey,@stockTotal=tftal
from stock
where id=@STOCKID

--האם להפיק תנועות יומן להעמסת עליות יבוא
select @IssueJurnalImport=IssueJurnalImport
from COMPANYDEFENITIONS
--מחשבים סה"כ במסמך
exec @MYERROR=UpInvTotal @stockid 
  if @MYERROR<>0 
  BEGIN
   RAISERROR ('PROCEDURE InvIssueDocument:, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
  END


--קריאה מבחוץ
--בדיקות לפני הפקה
exec @MYERROR=InvIssueDocumentCh  @STOCKID, @res output 
  if @MYERROR<>0 
  BEGIN
   RAISERROR ('PROCEDURE InvIssueDocument:, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
  END

if  @Res=0
    begin
        return 0
    end

select @documentid=documentid,@Vat=VatPrc 
from stock
where id=@stockid 


       
    
set @DocTotal=0
set @stockTotal=0

--קריאה לקבלה חישוב סה"כ לתשלום
If @DocumentID=2 Or @DocumentID=62 Or @DocumentID=87
begin
  exec @MYERROR=KbDocTotal  @stockid ,@DocTotal output
  if @MYERROR<>0 
  BEGIN
   RAISERROR ('PROCEDURE InvIssueDocument:, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
  END

--בדיקה שאין הפרש ביו החשבונית לקבלה
  if  @DocTotal<>@stockTotal
  begin
      exec @MYERROR=InvUpdateErrorMessage @STOCKID,@STOCKID,0,'StockMoves.tftal',89,1
      return 0			
  end        
end


if (select count(*) from intererrmesg
where headerid=@STOCKID
and tbl=2
and err<>1)>0
begin
     return 0			
end



begin tran
select @SalesDoc=SalesDoc,@UpdatFJurnal=UpdatFJurnal,@ExportDoc=ExportDoc
from   documentsdef
where  documentid=@documentid

update stockmoves
set status=0
where status=10
and stockid=@STOCKID


update stock
set status=0
where status=10
and id=@STOCKID

--העמסת עליות יבוא 
If @DocumentID=53
   Set  @UpdatFJurnal=@IssueJurnalImport

set @res=0 
--הפקה
  begin
     exec @MYERROR=ISSUEDOC  @STOCKID, @SALESDOC,@UpdatFJurnal, @VAT,  @ExportDoc, @ACC, @RESULT         
  if @MYERROR<>0 
  BEGIN
   ROLLBACK TRAN
   RAISERROR ('PROCEDURE InvIssueDocument:, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
  END
  end


-- (SQL)UpdateInterFlag2"
----------------------------------------- 
--חנות וירטואלית
UPDATE Stock 
SET Stock.InterFlag = 2
WHERE (Stock.InterFlag=1 
AND  Stock.Status=1 
AND  Stock.ID=@STOCKID)


UPDATE Stock 
SET Stock.InterFlag = 2
WHERE (Stock.InterFlag=3 
AND  Stock.Status=1 
AND  Stock.ID=@STOCKID)
-----------------------------



SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN                                                                 
   -- ROLLBACK TRAN
    RAISERROR ('PROCEDURE InvIssueDocument:, ERROR %d ', 19, 1,@MYERROR) WITH LOG
    RETURN @MYERROR  
  END

	commit TRAN

 return (0)



GO
