/****** Object:  StoredProcedure [dbo].[PreAddBaseMoves]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 



CREATE     Procedure [dbo].[PreAddBaseMoves]
                 @StockID             int,
     @BranchID            int, 
     @UpdateRate       tinyint,  
     @DocDisc             tinyint
     
As
declare @MYERROR  int     

BEGIN TRAN       

select  @DocDisc=DocDiscount
from CompanyDefenitions


update ITempBaseDoc
set baseStockId=(select stockid
from stockmoves
where stockmoves.id=ITempBaseDoc.BaseDocMoveID)
where (ITempBaseDoc.baseStockId is null 
or ITempBaseDoc.baseStockId=0 )
and ITempBaseDoc.DocStockID=@StockID

create table #ITempBaseDoc(docstockid int,basedocmoveid int ,basestockid int,quantity float)

insert into #ITempBaseDoc(docstockid ,basedocmoveid,basestockid ,quantity )
select docstockid ,basedocmoveid,basestockid ,quantity 
from ITempBaseDoc


SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN
    rollback tran      
    RAISERROR ('PROCEDURE PreAddBaseMoves: 1, ERROR %d ', 19, 1,@MYERROR) WITH LOG
 return 0
 end  

declare @BaseStockID int

declare Base_cur cursor
FOR 
select   basestockid
from     #itempbasedoc
where    docstockid=@StockID
group by basestockid
FOR READ ONLY 

open Base_cur
---------------------------------------
fetch Base_cur into 
      @BaseStockID

WHILE @@FETCH_STATUS = 0
    begin
      insert into ITempBaseDoc
      select *
      from #ITempBaseDoc
      where  docstockid=@StockID
      and   BaseStockID=@BaseStockID  
   
                     
      exec AddBaseMoves @StockID,
                        @BaseStockID,  
		        @BranchID,           
		        @UpdateRate,  
		        @DocDisc,           
		        10 --status

      fetch Base_cur into @BaseStockID
 end
---------------------------------------

close Base_cur
deallocate Base_cur

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN
    rollback tran      
    RAISERROR ('PROCEDURE PreAddBaseMoves: 2, ERROR %d ', 19, 1,@MYERROR) WITH LOG
 return 0
  end  

update stockmoves
set status=10
where  id in( select i.BaseDocMoveId
from #itempbasedoc i
where docstockid=@StockID)
and   stockid=@StockID

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN
    rollback tran      
    RAISERROR ('PROCEDURE PreAddBaseMoves: 3, ERROR %d ', 19, 1,@MYERROR) WITH LOG
 return 0
  end  

delete 
from    #itempbasedoc
where   docstockid=@StockID

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN
    rollback tran      
    RAISERROR ('PROCEDURE PreAddBaseMoves: 4, ERROR %d ', 19, 1,@MYERROR) WITH LOG
 return 0
  end  
commit tran
return (0)



GO
