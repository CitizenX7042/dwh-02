/****** Object:  StoredProcedure [dbo].[KB_Cancellation]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
  
-----------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------
--KabalaCancel
--01/08/2021 Eitan  
-----------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------

CREATE PROCEDURE [dbo].[KB_Cancellation]
			   @StockIdToCancel int,
			   @MainDocId      int,
			   @USERID         int,
			   @BRANCHID       int,
               @KUPANUM        int,
			   @CashToCancel   tinyint,
			   @CheqsToCancel  tinyint,
			   @CreditToCancel tinyint,
			   @MATCHFLAG      tinyint  = 0,  --דגל האם לבטל התאמות
			   @StationID      Varchar(100),  --מזהה תחנה עבור טבלה זמנית להדפסות 
			   @Copies         int,           --מספר עותקים להדפסה
			   @SourceTaxFlag  int,            --דגל לחישוב נכוי במקור    
			   @MatchNum       int            --מספר התאמה
As
SET nocount on   

DECLARE		@fix				int,
			@MainStockId		int,
			@VatTransType		varchar(3),
			@VatFreeTranType	varchar(3),
			@MYERROR			int,
			@StockUpdate		int,
			@UpdateJurnal		int, 
			@LBatch				int,
			@RowCount			int,
			@Chdate				varchar(25),
            @Date				datetime,
			@CurrentNumber      int,
			@MAIN_CUR           VARCHAR(5),
			@KUPATNIKUI         VARCHAR(15),
			@KUPATCHEQS         VARCHAR(15),
			@KUPATCRED          VARCHAR(15),
			@CP_DETAILS         VARCHAR(250),
			@SourceTax          FLOAT,
			@SourceTaxDlrCur    VARCHAR(15),
			@SourceTaxDlr		FLOAT,
			@SourceTaxCur		VARCHAR(15),
			@CashAccount        varchar(15),
			@MatchToCancel      int,
			@JurnalTransSBA     int,
			@LAST4DIG2REF       int,
			@SufToCancle        FLOAT,
			@Acct               VARCHAR(15),
			@AcctName           VARCHAR(50),
			@JurnalMatchID      int,
			@JurnalMatchSum     FLOAT,
			@BALANC             FLOAT,
			@EvalCurr           VARCHAR(5)


		


SET TRANSACTION ISOLATION level read committed 
BEGIN TRAN 
      
SET @Chdate=convert(varchar(25),GetDate(),107)
SET @Date=convert(datetime,@Chdate,0)
SET @CP_DETAILS=NULL


IF @StockIdToCancel<1 or  @StockIdToCancel is NULL 
begin
    ROLLBACK TRAN
    RETURN 54
END

IF @MainDocId<1 or @MainDocId is NULL
begin
    ROLLBACK TRAN
    RETURN 55
END

IF  @USERID  is NULL
begin
    ROLLBACK TRAN
    RETURN 56
END

--עדכון משתנה של מטבע מוביל
SELECT @MAIN_CUR = MainCurrency,@KUPATNIKUI=DeductAcc FROM CompanyDefenitions
SET @MYERROR = @@ERROR
IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 1, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

IF(SELECT Stock.Currency FROM Stock WHERE ID = @StockIdToCancel)= @MAIN_CUR 
Begin
   SET @CashAccount = (SELECT CompanyDefenitions.CashAcc FROM CompanyDefenitions)
   SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 2, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END
 ELSE
BEGIN
   SET @CashAccount = (SELECT CompanyDefenitions.CashDlrAcc FROM CompanyDefenitions)
   SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 3, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END

IF(SELECT Stock.Currency FROM Stock WHERE ID = @StockIdToCancel)= @MAIN_CUR 
BEGIN
  set @EvalCurr = (SELECT CompanyDefenitions.EvalCurrency  FROM CompanyDefenitions) 
END
ELSE
BEGIN
  set @EvalCurr = @MAIN_CUR
END

SELECT @fix=documentsdef.FixNumerator,@VatTransType=VatTransType
,@VatFreeTranType=VatFreeTranType,@StockUpdate=StockUpdate ,@UpdateJurnal=UpdatFJurnal
FROM documentsdef
WHERE documentsdef.documentid=CASE WHEN @CashToCancel = 1 THEN 48 WHEN @CheqsToCancel = 1 THEN 34 WHEN @CreditToCancel = 1 THEN 41 END
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 4, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

SET @MYERROR = @@ERROR
SET @rowcount = @@rowcount
IF @MYERROR <> 0 or @rowcount=0
  BEGIN
    ROLLBACK TRAN
    RAISERROR ('PROCEDURE KB_Cancellation: 5 , ERROR %d ', 19, 1,@MYERROR) WITH LOG
    RETURN @MYERROR  
  END

SET   @LBatch=0 

--בדיקה האם יש חשבון מרכז
select @Acct = AssignKey from Accounts inner join stock on accounts.AccountKey = Stock.AccountKey where stock.id =  @StockIdToCancel
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 74, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
IF @Acct is null
BEGIN
select @Acct = accounts.AccountKey  from Accounts inner join stock on accounts.AccountKey = Stock.AccountKey where stock.id =  @StockIdToCancel
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 75, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END
select @AcctName  = accounts.FullName   from Accounts  where accounts.AccountKey =  @Acct
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 76, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END


--חישוב הסכום לביטול על פי אמצעי התשלום
IF @CashToCancel = 1
BEGIN
   SELECT @SufToCancle = SuF FROM CashPays WHERE StockID = @StockIdToCancel
   SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 6, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END
IF @CheqsToCancel = 1
BEGIN
   SELECT @SufToCancle = sum(SuF) FROM Cheqs  WHERE StockID = @StockIdToCancel
   SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 7, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END
IF @CreditToCancel = 1
BEGIN
   SELECT @SufToCancle = sum(SuF) FROM CreditPays WHERE StockID = @StockIdToCancel
   SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 8, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END

INSERT INTO STOCK ( DOCUMENTID, DOCNUMBER, STATUS,TFtal,ACCOUNTKEY, ACCOUNTNAME, ADDRESS, CITY, PHONE, DUEDATE, PAYDATE, COPIES, TRANSTYPE, VATFREETRANSTYPE, DISCOUNTPRC, VATPRC, REFERENCE, REMARKS, MARKETINGNET, PRINTSTYLE, DETAILS, 
WAREHOUSE, AGENT, EVALCURRENCY, PROTOCOLID, EXPORTADDR, USEFID, BRANCHID, RATE, MAINRATE, DISCOUNTPRCR,  REF3, COSTCODE, MARKETINGNETNUM, CURRENCY,BATCH,valuedate,issuedate,ExtraText1,ExtraText2,ExtraText3,
ExtraText4,ExtraText5,ExtraSum1,ExtraSum2,ExtraSum3,miv,KUPANUM,quantity,Contact,BaseOrderStockId,OriginalPrinted,Osek874,CRMAcc,DistLine,ContactMail,ExFile,Vatfree,ExtraNum1,ExtraNum2,ExtraDate1,ExtraDate2,PaymentMethodCode)
SELECT EXPR10 = CASE WHEN @CashToCancel = 1 THEN 48 WHEN @CheqsToCancel = 1 THEN 34 WHEN @CreditToCancel = 1 THEN 41 END , STOCK.DOCNUMBER, STOCK.Status ,@SufToCancle as EXP1 ,STOCK.ACCOUNTKEY, STOCK.ACCOUNTNAME, 
STOCK.ADDRESS, STOCK.CITY, STOCK.PHONE,EXPR11 = CASE WHEN @CashToCancel = 1 THEN @Date else STOCK.DUEDATE END, STOCK.PAYDATE, @Copies, STOCK.TRANSTYPE, STOCK.VATFREETRANSTYPE, STOCK.DISCOUNTPRC, STOCK.VATPRC, Stock.DocNumber, ' ביטול על סמך קבלה ' + cast(Stock.DocNumber as varchar ) , STOCK.MARKETINGNET, STOCK.PRINTSTYLE, 
(ISNULL(cast (Details as varchar), '') + ' ' + (ISNULL(cast(' ביטול על סמך קבלה ' as varchar ), '') + cast(Stock.DocNumber as varchar ) ) )/*STOCK.DETAILS*/, STOCK.WAREHOUSE, STOCK.AGENT, @EvalCurr, STOCK.PROTOCOLID, STOCK.EXPORTADDR, @USERID AS EXPR2, @BRANCHID AS EXPR3, STOCK.RATE, STOCK.MAINRATE, STOCK.DISCOUNTPRCR, STOCK.REF3, STOCK.COSTCODE, 
STOCK.MARKETINGNETNUM, STOCK.CURRENCY,9999 AS MYBATCH ,@Date as d1,@Date as d2,stock.ExtraText1,stock.ExtraText2,stock.ExtraText3,stock.ExtraText4,stock.ExtraText5,stock.ExtraSum1,stock.ExtraSum2,stock.ExtraSum3,0,
@KUPANUM,stock.quantity,STOCK.CONTACT,0,0,STOCK.Osek874,stock.CRMAcc,Stock.DistLine,Stock.ContactMail,Stock.ExFile,Stock.VatFree,
STOCK.ExtraNum1,STOCK.ExtraNum2,STOCK.ExtraDate1,STOCK.ExtraDate2,Stock.PaymentMethodCode
FROM STOCK 
WHERE STOCK.DOCUMENTID=@MainDocId
AND   STOCK.ID=@StockIdToCancel
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 9, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END


SET @MainStockId=@@identity

SELECT @CurrentNumber =  DocumentsDef.CurrenFNumber  FROM DocumentsDef WHERE DocumentsDef.DocumentID = CASE WHEN @CashToCancel = 1 THEN 48 WHEN @CheqsToCancel = 1 THEN 34 WHEN @CreditToCancel = 1 THEN 41 END 
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 10, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

SET @MYERROR = @@ERROR
SET @rowcount = @@rowcount
  IF @MYERROR <> 0 or @rowcount=0
  BEGIN
    ROLLBACK TRAN
    RAISERROR ('PROCEDURE KB_Cancellation: 11 , ERROR %d ', 19, 1,@MYERROR) WITH LOG
    RETURN @MYERROR  
  END
  --***עדכון ספרור המסמך הבא
UPDATE Stock SET Stock.DocNumber = @CurrentNumber WHERE Stock.ID = @MainStockId
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 12, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE DocumentsDef  SET DocumentsDef.CurrenFNumber = @CurrentNumber+1, LastDocDate = cast(convert(varchar(8),getdate(),1) as datetime)  FROM DocumentsDef WHERE DocumentsDef.DocumentID= CASE WHEN @CashToCancel = 1 THEN 48 WHEN @CheqsToCancel = 1 THEN 34 WHEN @CreditToCancel = 1 THEN 41 END
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 13, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE Stock SET stock.KUTime = convert(int,DATEPART(HOUR, GETDATE())*60 +DATEPART(MINUTE, GETDATE()) ),stock.KuDate = cast(convert(varchar(8),getdate(),1) as datetime),
BaseCancelDocID=@StockIdToCancel  WHERE Stock.ID = @MainStockId
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 14, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END


--עדכון הקבלה המקורית בביטול
  UPDATE Stock SET stock.DocCancel = 1,stock.DocCancelDate  = cast(convert(varchar(8),getdate(),1) as datetime),Stock.DocCancelUsefID = @USERID ,
  Stock.DocCancelTime = convert(int,DATEPART(HOUR, GETDATE())*60 +DATEPART(MINUTE, GETDATE()) )  WHERE Stock.ID = @StockIdToCancel
  SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 15, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

 --עדכון טבלה זמנית במזהה מקורי שבוטל ובמזהה החדש לצורך הדפסות
 IF @Copies > 0
  BEGIN
    INSERT INTO TempChkKabIssue(StockID,TblID,Station) select @StockIdToCancel,@MainStockId,@StationID 
	SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 16, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
  END
--הכנסת שורה לטבלת מזומנים
IF @CashToCancel = 1
BEGIN
INSERT INTO CashPays (  DatF ,SuF,Currency,Status,SuFDlr,CurrencyDlr,Details,StockID,SourceID,SourceTax,TaxCurrencyDlr,TaxSumDlr,BranchID,KupaNum,CustomerID,CustomerIDSort,KupaNumFix,Description,EltCurrency,EltSuF,EltFlag
,EltSuFIs,RecSuF,RecFlag)
SELECT cast(convert(varchar(8),getdate(),1) as datetime) as EXPR1,SuF * -1,Currency,Status,SuFDlr * -1,CurrencyDlr,Details,@MainStockId,SourceID,0,TaxCurrencyDlr,TaxSumDlr,BranchID,KupaNum,CustomerID,CustomerIDSort,KupaNumFix,Description,EltCurrency,EltSuF,EltFlag
,EltSuFIs,RecSuF,RecFlag FROM CashPays WHERE StockID = @StockIdToCancel
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 17, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--עדכון פרטים למזומן
SELECT @CP_DETAILS = DETAILS
FROM CASHPAYS
WHERE STOCKID=@MainStockId
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 18, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

IF @CP_DETAILS IS NULL
BEGIN
   SELECT @CP_DETAILS = REMARKS
   FROM STOCK
   WHERE ID=@MainStockId
END
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 19, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END


IF(SELECT STOCK.CURRENCY FROM Stock WHERE Stock.ID=@StockIdToCancel)= @MAIN_CUR
BEGIN
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 20, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--רשומת כותרת הנהח לקבלת שח מזומן 
 INSERT INTO JurnalTrans (ExFile, IssueDate, KupaNum, TransType, Ref2, StockID, Branch, DatF3, Ref3, Quant, CostCode, USEFID, BatchNo, ValueDate, DueDate, Description, Referance, Changable, SUF,suFDlr, TransDebID, TransCredID, 
 CredName, DebName, Status, CurrencyCode,BDate, Hour,DocumentID )
SELECT DISTINCT Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime) as Expr6, Stock.Kupanum, Stock.TransType, Stock.Reference, Stock.ID, Stock.BranchID, Stock.IssueDate, Stock.Ref3, Stock.Quantity, Stock.CostCode, Stock.USEFID AS Expr1, Stock.Batch, Stock.ValueDate, 
Stock.ValueDate, Stock.Remarks, Stock.DocNumber, 0 AS Expr4, CASHPAYS.SUF *-1 AS Expr2,CASHPAYS.SuFDlr *-1 AS Expr6, @Acct, @CashAccount AS Expr3, Accounts_1.FullName, @AcctName , 1 AS Expr5, CashPays.CurrencyDlr
,Stock.KuDate, Stock.KUTime,stock.DocumentID
FROM CompanyDefenitions, Accounts AS Accounts_1, (Stock INNER JOIN CashPays ON Stock.ID = CashPays.StockID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey
WHERE (((Stock.ID)=@MainStockId) AND ((Accounts_1.AccountKey)=@CashAccount))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 21, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END

--רשומת כותרת הנהח לקבלת מטח מזומן 
IF(SELECT STOCK.CURRENCY FROM Stock WHERE Stock.ID=@StockIdToCancel)<> @MAIN_CUR
BEGIN
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 22, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 INSERT INTO JurnalTrans (ExFile, IssueDate, KupaNum, TransType, Ref2, StockID, Branch, DatF3, Ref3, Quant, CostCode, USEFID, BatchNo, ValueDate, DueDate, Description, Referance, Changable, SUFDLR, TransDebID, TransCredID, 
CredName, DebName, Status, CurrencyCode, SUF,BDate, Hour,DocumentID )
SELECT DISTINCT Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime) as EXPR26, Stock.Kupanum, Stock.TransType, Stock.Reference, Stock.ID, Stock.BranchID, Stock.IssueDate, Stock.Ref3, Stock.Quantity, Stock.CostCode, 
Stock.UseFID AS Expr1, Stock.Batch, Stock.ValueDate, Stock.ValueDate, Stock.Remarks, Stock.DocNumber, 0 AS Expr6, CASHPAYS.SUF *-1  AS Expr5, @Acct, @CashAccount AS Expr4, Accounts_1.FullName, @AcctName, 
1 AS Expr2, Stock.Currency,CASHPAYS.SuFDlr *-1 /*(CASHPAYS.SUF *-1 * Stock.MainRate)*/ AS Expr3
,Stock.KuDate, Stock.KUTime,stock.DocumentID
FROM Accounts AS Accounts_1, (Stock INNER JOIN CashPays ON Stock.ID = CashPays.StockID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey
WHERE (((Stock.ID)=@MainStockId) AND ((Accounts_1.AccountKey)=@CashAccount))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 23, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

END

--במידה ויש ניכוי במקור יעודכן בהמשך
IF @SourceTaxFlag = 0
BEGIN
--תנועות יומן חובה לכותרות הנהח
INSERT INTO JurnalTransMoves ( TransID, AccountKey, DebitCredit, SuF, SuFDlr )
SELECT DISTINCT JurnalTrans.TransID, JurnalTrans.TransDebID, 1 AS Expr1, JurnalTrans.suf, JurnalTrans.SuFDlr
FROM Stock INNER JOIN JurnalTrans ON Stock.ID = JurnalTrans.StockID
WHERE (((Stock.ID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 72, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
--תנועות יומן זכות לכותרות הנהח
INSERT INTO JurnalTransMoves ( TransID, AccountKey, DebitCredit, SuF, SuFDlr )
SELECT DISTINCT JurnalTrans.TransID, JurnalTrans.TransCredID, 0 AS Expr1, JurnalTrans.suf, JurnalTrans.SuFDlr
FROM Stock INNER JOIN JurnalTrans ON Stock.ID = JurnalTrans.StockID
WHERE (((Stock.ID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 73, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END
--עדכון יתרת לקוח
--UPDATE  ACCOUNTS 
--SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE - STOCK.TFTAL
--FROM  ACCOUNTS, STOCK 
--WHERE (((STOCK.ID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@Acct ));
UPDATE  ACCOUNTS SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE - GRP.suf   FROM  ACCOUNTS inner join 
(select ACCOUNTS.AccountKey , sum(jurnaltrans.suf) as suf FROM  ACCOUNTS, JurnalTrans  WHERE (((JurnalTrans.StockID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@Acct))
group by ACCOUNTS.BALANCE,ACCOUNTS.AccountKey,JurnalTrans.StockID  )as GRP  on Accounts.AccountKey = GRP.AccountKey 
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 24, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--עדכון יתרת כרטיס קופה
--UPDATE  ACCOUNTS 
--SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE + STOCK.TFTAL
--FROM  ACCOUNTS, STOCK 
--WHERE (((STOCK.ID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@CashAccount))
UPDATE  ACCOUNTS SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE + GRP.suf   FROM  ACCOUNTS inner join 
(select ACCOUNTS.AccountKey , sum(jurnaltrans.suf) as suf FROM  ACCOUNTS, JurnalTrans  WHERE (((JurnalTrans.StockID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@CashAccount))
group by ACCOUNTS.BALANCE,ACCOUNTS.AccountKey,JurnalTrans.StockID  )as GRP  on Accounts.AccountKey = GRP.AccountKey 
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 25, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 END



--הוצאת שקים מהקופה

IF @CheqsToCancel = 1
BEGIN
--בדיקה האם שקים לפיקדון
IF(SELECT Stock.pikadon FROM Stock WHERE ID = @StockIdToCancel)= 0 
BEGIN
SET @KUPATCHEQS = (SELECT CompanyDefenitions.cheqAcc FROM CompanyDefenitions)
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 26, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 END
ELSE
 BEGIN
SET @KUPATCHEQS = (SELECT CompanyDefenitions.cheqPikAcc  FROM CompanyDefenitions)
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 26, ERROR %d ', 86, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END

UPDATE  Cheqs   SET Cheqs.DepositID = @MainStockId ,DepositFlag = 1
FROM cheqs inner join  Stock on Cheqs.StockID = Stock.ID 
     WHERE (((Cheqs.DepositID)=0) AND ((Stock.ID)=@StockIdToCancel) AND ((Cheqs.Currency)=Stock.Currency) AND ((Cheqs.BadCheqFlag)=0)  AND ((Cheqs.Status)=1))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 27, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--רשומת כותרת הנהח להוצאת שקים ש"ח 
IF(SELECT STOCK.CURRENCY FROM Stock WHERE Stock.ID=@StockIdToCancel)= @MAIN_CUR
BEGIN
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 28, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

INSERT INTO JurnalTrans ( ExFile, IssueDate, KupaNum, TransType, StockID, Branch, DatF3, Ref3, Quant, CostCode, UseFID, Referance, Status, DueDate, ValueDate, TransDebID, DebName, TransCredID, CredName, Ref2, BatchNo, 
Changable, suF, Description, CurrencyCode, suFDlr,BDate, Hour,DocumentID,ExtraNum1,ExtraNum2,ExtraDate1,ExtraDate2)  
SELECT Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.Kupanum, Stock.TransType, Stock.ID, Stock.BranchID, Stock.IssueDate, Cheqs.CheqNumber, Stock.Quantity, Stock.CostCode, Stock.UseFID AS Expr1, 
Stock.DocNumber, 1 AS Expr3,Cheqs.ValueDate AS Expr7, Stock.ValueDate, @Acct, @AcctName, @KUPATCHEQS AS Expr6, Accounts_1.FullName, Stock.Reference, Stock.Batch, 0 AS Expr2, Cheqs.SuF AS Expr4, Stock.Remarks, 
Cheqs.CurrencyDlr AS Expr5, Cheqs.SuFDlr  ,Stock.KuDate, Stock.KUTime,stock.DocumentID,stock.ExtraNum1 ,stock.ExtraNum2,stock.ExtraDate1 ,stock.ExtraDate2 
FROM Accounts AS Accounts_1, (Stock INNER JOIN Cheqs ON Stock.ID = Cheqs.DepositID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey  
WHERE (((Stock.ID)=@MainStockId) AND ((Cheqs.ValueDate)<Stock.ValueDate) AND ((Accounts_1.AccountKey)= @KUPATCHEQS))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 29, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

INSERT INTO JurnalTrans ( ExFile, IssueDate, KupaNum, TransType, StockID, Branch, DatF3, Ref3, Quant, CostCode, UsefID, Referance, Status, DueDate, ValueDate, TransDebID, DebName, TransCredID, CredName, Ref2, BatchNo, 
Changable, suF, Description, CurrencyCode, suFDlr,BDate, Hour,DocumentID,ExtraNum1,ExtraNum2,ExtraDate1,ExtraDate2)  
SELECT Stock.ExFile,  cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.Kupanum, Stock.TransType, Stock.ID, Stock.BranchID, Stock.IssueDate, Cheqs.CheqNumber, Stock.Quantity, Stock.CostCode,   Stock.UseFID AS Expr1, 
Stock.DocNumber, 1 AS Expr3,Cheqs.ValueDate AS Expr7,   Stock.ValueDate, @Acct, @AcctName, @KUPATCHEQS AS Expr6,   Accounts_1.FullName, Stock.Reference, Stock.Batch, 0 AS Expr2, Cheqs.SuF AS Expr4,Stock.Remarks, 
Cheqs.CurrencyDlr AS Expr5, Cheqs.SuFDlr,Stock.KuDate, Stock.KUTime,stock.DocumentID,stock.ExtraNum1 ,stock.ExtraNum2,stock.ExtraDate1 ,stock.ExtraDate2  
FROM Accounts AS Accounts_1, (Stock INNER JOIN Cheqs ON Stock.ID = Cheqs.DepositID) INNER   JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey  
WHERE (((Stock.ID)=@MainStockId) AND ((Cheqs.ValueDate)=Stock.ValueDate) AND ((Accounts_1.AccountKey)= @KUPATCHEQS))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 30, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

INSERT INTO JurnalTrans ( ExFile, IssueDate, KupaNum, TransType, StockID, Branch, DatF3, Ref3, Quant, CostCode, UseFID, Referance, Status, DueDate, ValueDate, TransDebID, DebName, TransCredID, CredName, Ref2, BatchNo, 
Changable, suF, Description, CurrencyCode, suFDlr,BDate, Hour,DocumentID,ExtraNum1,ExtraNum2,ExtraDate1,ExtraDate2 )  
SELECT Stock.ExFile,  cast(convert(varchar(8),getdate(),1) as datetime) AS Expr26, Stock.Kupanum, Stock.TransType, Stock.ID, Stock.BranchID, Stock.IssueDate, Cheqs.CheqNumber, Stock.Quantity, Stock.CostCode,Stock.UseFID AS Expr1,Stock.DocNumber, 1 AS Expr3, 
Cheqs.ValueDate AS Expr7, Stock.ValueDate, @Acct, @AcctName, @KUPATCHEQS AS Expr6, Accounts_1.FullName, Stock.Reference, Stock.Batch, 0 AS Expr2, Cheqs.SuF AS Expr4, Stock.Remarks, 
Cheqs.CurrencyDlr AS Expr5, Cheqs.SuFDlr  ,Stock.KuDate, Stock.KUTime,stock.DocumentID,stock.ExtraNum1 ,stock.ExtraNum2,stock.ExtraDate1 ,stock.ExtraDate2  
FROM Accounts AS Accounts_1, (Stock INNER JOIN Cheqs ON Stock.ID = Cheqs.DepositID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey  
WHERE (((Stock.ID)=@MainStockId) AND ((Cheqs.ValueDate)>Stock.ValueDate) AND ((Accounts_1.AccountKey)= @KUPATCHEQS))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 31, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END

--רשומת כותרת הנהח להוצאת שקים מט"ח 
IF(SELECT STOCK.CURRENCY FROM Stock WHERE Stock.ID=@StockIdToCancel)<> @MAIN_CUR
BEGIN
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 28, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
SET @KUPATCHEQS = (SELECT CompanyDefenitions.cheqDlrAcc FROM CompanyDefenitions)
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 77, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

IF(SELECT STOCK.CURRENCY FROM Stock WHERE Stock.ID=@StockIdToCancel)<> @MAIN_CUR
BEGIN
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 32, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

INSERT INTO JurnalTrans (ExFile,  IssueDate, KupaNum, TransType, StockID, Branch, DatF3, Ref3, Quant, CostCode, UseFID, Status, Referance, DueDate, ValueDate, TransDebID, DebName, TransCredID, CredName, Ref2, BatchNo, 
CurrencyCode, Changable, suFDlr, Description, suF,BDate, Hour,DocumentID,ExtraNum1,ExtraNum2,ExtraDate1,ExtraDate2 )
SELECT  Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.Kupanum, Stock.TransType, Stock.ID, Stock.BranchID, Stock.IssueDate, Cheqs.CheqNumber, Stock.Quantity, Stock.CostCode, Stock.UseFID AS Expr5, 
1 AS Expr3, Stock.DocNumber, Cheqs.ValueDate AS Expr1, Stock.ValueDate, @Acct, @AcctName, @KUPATCHEQS AS Expr6, Accounts_1.FullName, Stock.Reference, Stock.Batch, Stock.Currency, 0 AS Expr2, Cheqs.SuF AS Expr4, Stock.Remarks, Cheqs.SuFDlr
,Stock.KuDate, Stock.KUTime,stock.DocumentID,stock.ExtraNum1 ,stock.ExtraNum2,stock.ExtraDate1 ,stock.ExtraDate2
FROM Accounts AS Accounts_1, (Stock INNER JOIN Cheqs ON Stock.ID = Cheqs.DepositID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey
WHERE (((Stock.ID)=@MainStockId) AND ((Cheqs.ValueDate)<Stock.ValueDate) AND ((Accounts_1.AccountKey)=@KUPATCHEQS))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 33, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

INSERT INTO JurnalTrans (ExFile, IssueDate, KupaNum, TransType, StockID, Branch, DatF3, Ref3, Quant, CostCode, UseFID, Status, Referance, DueDate, ValueDate, TransDebID, DebName, TransCredID, CredName, Ref2, BatchNo, 
CurrencyCode, Changable, suFDlr, Description, suf,BDate, Hour,DocumentID,ExtraNum1,ExtraNum2,ExtraDate1,ExtraDate2 )
SELECT Stock.ExFile,  cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.Kupanum, Stock.TransType, Stock.ID, Stock.BranchID, Stock.IssueDate, Cheqs.CheqNumber, Stock.Quantity, Stock.CostCode, Stock.UseFID AS Expr1, 
1 AS Expr3, Stock.DocNumber, Cheqs.ValueDate AS Expr6, Stock.ValueDate, @Acct, @AcctName, @KUPATCHEQS AS Expr5, Accounts_1.FullName, Stock.Reference, Stock.Batch, Stock.Currency, 0 AS Expr2, Cheqs.SuF AS Expr4, Stock.Remarks, Cheqs.SuFDlr
,Stock.KuDate, Stock.KUTime,stock.DocumentID,stock.ExtraNum1 ,stock.ExtraNum2,stock.ExtraDate1 ,stock.ExtraDate2
FROM Accounts AS Accounts_1, (Stock INNER JOIN Cheqs ON Stock.ID = Cheqs.DepositID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey
WHERE (((Stock.ID)=@MainStockId) AND ((Cheqs.ValueDate)=Stock.ValueDate) AND ((Accounts_1.AccountKey)=@KUPATCHEQS))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 34, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

INSERT INTO JurnalTrans (ExFile,  IssueDate, KupaNum, TransType, StockID, Branch, DatF3, Ref3, Quant, CostCode, UseFID, Status, Referance, DueDate, ValueDate, TransDebID, DebName, TransCredID, CredName, Ref2, BatchNo, 
CurrencyCode, Changable, suFDlr, Description, suf ,BDate, Hour,DocumentID,ExtraNum1,ExtraNum2,ExtraDate1,ExtraDate2 )
SELECT  Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.Kupanum, Stock.TransType, Stock.ID, Stock.BranchID, Stock.IssueDate, Cheqs.CheqNumber, Stock.Quantity, Stock.CostCode, Stock.UseFID AS Expr1, 1 AS Expr3, Stock.DocNumber, Cheqs.ValueDate AS Expr6, 
Stock.ValueDate, @Acct, @AcctName, @KUPATCHEQS AS Expr5, Accounts_1.FullName, Stock.Reference, Stock.Batch, Stock.Currency, 0 AS Expr2, Cheqs.SuF AS Expr4, Stock.Remarks, Cheqs.SuFDlr
,Stock.KuDate, Stock.KUTime,stock.DocumentID,stock.ExtraNum1 ,stock.ExtraNum2,stock.ExtraDate1 ,stock.ExtraDate2
FROM Accounts AS Accounts_1, (Stock INNER JOIN Cheqs ON Stock.ID = Cheqs.DepositID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey
WHERE (((Stock.ID)=@MainStockId) AND ((Cheqs.ValueDate)>Stock.ValueDate) AND ((Accounts_1.AccountKey)=@KUPATCHEQS))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 35, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END
END

--תנועות יומן חובה לכותרות הנהח
--במידה ויש ניכוי במקור יעודכן בהמשך
IF @SourceTaxFlag = 0
BEGIN
INSERT INTO JURNALTRANSMOVES ( TRANSID, ACCOUNTKEY, DEBITCREDIT, SUF, SUFDLR )
SELECT DISTINCT JURNALTRANS.TRANSID, JURNALTRANS.TransDebID, 1 AS EXPR1, JURNALTRANS.SUF, JURNALTRANS.SUFDLR
FROM Stock INNER JOIN JurnalTrans ON Stock.ID = JurnalTrans.StockID
WHERE Stock.ID=@MainStockId
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 36, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--תנועות יומן זכות לכותרות הנהח
INSERT INTO JURNALTRANSMOVES ( TRANSID, ACCOUNTKEY, DEBITCREDIT, SUF, SUFDLR )
SELECT DISTINCT JurnalTrans.TransID, JurnalTrans.TransCredID, 0 AS Expr1, JurnalTrans.suf, JURNALTRANS.SUFDLR
FROM Stock INNER JOIN JurnalTrans ON Stock.ID = JurnalTrans.StockID
WHERE Stock.ID=@MainStockId
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 37, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 END
--עדכון יתרה בכרטיס הלקוח
--UPDATE  ACCOUNTS 
--SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE - STOCK.TFTAL
--FROM  ACCOUNTS, STOCK 
--WHERE (((STOCK.ID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@Acct ))
UPDATE  ACCOUNTS SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE - GRP.suf   FROM  ACCOUNTS inner join 
(select ACCOUNTS.AccountKey , sum(jurnaltrans.suf) as suf FROM  ACCOUNTS, JurnalTrans  WHERE (((JurnalTrans.StockID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@Acct))
group by ACCOUNTS.BALANCE,ACCOUNTS.AccountKey,JurnalTrans.StockID  )as GRP  on Accounts.AccountKey = GRP.AccountKey 
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 38, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--עדכון יתרת קופת שקים
IF(SELECT STOCK.CURRENCY FROM Stock WHERE Stock.ID=@StockIdToCancel)= @MAIN_CUR
BEGIN
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 28, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 SET @KUPATCHEQS = (SELECT CompanyDefenitions.cheqAcc FROM CompanyDefenitions)
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 26, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END

--UPDATE  ACCOUNTS SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE + STOCK.TFTAL
--FROM  ACCOUNTS, STOCK WHERE (((STOCK.ID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@KUPATCHEQS));
UPDATE  ACCOUNTS SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE + GRP.suf   FROM  ACCOUNTS inner join 
(select ACCOUNTS.AccountKey , sum(jurnaltrans.suf) as suf FROM  ACCOUNTS, JurnalTrans  WHERE (((JurnalTrans.StockID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@KUPATCHEQS))
group by ACCOUNTS.BALANCE,ACCOUNTS.AccountKey,JurnalTrans.StockID  )as GRP  on Accounts.AccountKey = GRP.AccountKey 
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 39, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

 END

 --הפקדת אשראי ידני-------

IF @CreditToCancel = 1
BEGIN
 --הערה - לבדוק עבודה מול סניף /קופה
 UPDATE  CreditPays   SET CreditPays.DepositID = @MainStockId ,DepositFlag = 1
FROM CreditPays inner join  Stock on CreditPays.StockID = Stock.ID 
     WHERE (((CreditPays.DepositID)=0) AND ((Stock.ID)=@StockIdToCancel) AND ((CreditPays.Currency)=Stock.Currency) AND ((CreditPays.fShvaFlag)=0)  AND ((CreditPays.Status)=1))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 40, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

 IF(SELECT STOCK.CURRENCY FROM Stock WHERE Stock.ID=@StockIdToCancel)= @MAIN_CUR
 BEGIN
  SET @MYERROR = @@ERROR
  IF @MYERROR <> 0
   BEGIN
     RAISERROR ('PROCEDURE KB_Cancellation: 41, ERROR %d ', 19, 1,@MYERROR) WITH LOG
     RETURN @MYERROR  
   END
 --פקודת יומן מרוכזרת באשראי ידני ש"ח
 select @JurnalTransSBA = COMPANYDEFENITIONS.JTSba from COMPANYDEFENITIONS
 SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 42, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

 IF @JurnalTransSBA = 0
 BEGIN
 INSERT INTO JurnalTrans ( BDate, Hour, TransType, ExFile, IssueDate, KupaNum, StockID, Branch, DatF3, Ref2, Ref3, Quant, CostCode, UseFID, BatchNo, ValueDate, DueDate, Description, Referance, Changable, suF, suFDlr, 
 TransDebID, DebName, CredName, Status, CurrencyCode, TransCredID,DocumentID )
SELECT Stock.KuDate, Stock.KUTime, Stock.TransType, Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.KupaNum, Stock.ID, 
Stock.BranchID, Stock.IssueDate, Stock.Reference /*Stock.DocNumber*/, stock.ref3, Stock.Quantity, 
Stock.CostCode, Stock.UseFID AS Expr1, Stock.Batch, Stock.ValueDate, 
CreditPaysSplit.DatF AS Expr2, Stock.Remarks, Stock.DocNumber, 0 AS Exp1, 
SUM(CreditPaysSplit.SuF) AS Expr3, SUM(CreditPaysSplit.SuFDlr), @Acct, 
@AcctName, Accounts_1.FullName, 1 AS Expr6, 
CreditPays.CurrencyDlr AS Expr4, CreditPays.KupaKey,stock.DocumentID
FROM (((Stock INNER JOIN CreditPays ON Stock.ID = CreditPays.DepositID) INNER JOIN CreditPaysSplit ON CreditPays.ID = CreditPaysSplit.CreditPayID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey) INNER JOIN Accounts AS Accounts_1 ON CreditPays.KupaKey = Accounts_1.AccountKey
WHERE (((Stock.ID)=@MainStockId))
GROUP BY Stock.KuDate, Stock.KUTime, STOCK.EXFILE,STOCK.KUPANUM, STOCK.ID, 
STOCK.BRANCHID, STOCK.ISSUEDATE,STOCK.QUANTITY, 
STOCK.COSTCODE, STOCK.USEFID, STOCK.BATCH, STOCK.VALUEDATE,
STOCK.REMARKS, STOCK.DOCNUMBER,STOCK.ACCOUNTKEY, stock.ref3,
ACCOUNTS.FULLNAME, ACCOUNTS_1.FULLNAME,CREDITPAYS.CURRENCYDLR,
CREDITPAYSSPLIT.DATF, CREDITPAYS.KUPAKEY, CREDITPAYS.fdealtype, STOCK.TRANSTYPE,stock.DocumentID,Stock.Reference
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 43, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 END


 ELSE
 BEGIN
 select @LAST4DIG2REF = COMPANYDEFENITIONS.LAST4DIG2REF from COMPANYDEFENITIONS
 INSERT INTO JurnalTrans ( BDate, Hour, TransType, ExFile, IssueDate, KupaNum, StockID, Branch, DatF3, Ref2, Ref3, Quant, CostCode, UseFID, BatchNo, ValueDate, DueDate, Description, Referance, Changable, suF, suFDlr, 
 TransDebID, DebName, CredName, Status, CurrencyCode, TransCredID,DocumentID )
SELECT Stock.KuDate, Stock.KUTime, Stock.TransType, Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.KupaNum, Stock.ID, Stock.BranchID, Stock.IssueDate,
  CASE WHEN @LAST4DIG2REF = 1 THEN CreditPays.Last4dig ELSE Stock.Reference /*Stock.DocNumber*/ END, CASE WHEN @LAST4DIG2REF = 1 THEN Stock.Reference  WHEN STOCK.Ref3 > 0 THEN STOCK.Ref3 ELSE CreditPays.fShovar END
 , Stock.Quantity, Stock.CostCode, Stock.UseFID AS Expr1, Stock.Batch, Stock.ValueDate, CreditPaysSplit.DatF AS Expr2, Stock.Remarks, Stock.DocNumber, 0 AS Exp1, CreditPaysSplit.SuF AS Expr3, 
 CreditPaysSplit.SuFDlr, @Acct, @AcctName, Accounts_1.FullName, 1 AS Expr6, CreditPays.CurrencyDlr AS Expr4, CreditPays.KupaKey,stock.DocumentID
FROM (((Stock INNER JOIN CreditPays ON Stock.ID = CreditPays.DepositID) INNER JOIN CreditPaysSplit ON CreditPays.ID = CreditPaysSplit.CreditPayID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey) INNER JOIN Accounts AS Accounts_1 ON CreditPays.KupaKey = Accounts_1.AccountKey
WHERE (((Stock.ID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 44, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 END
 end
ELSE -- מט"ח
 BEGIN
 IF @JurnalTransSBA = 0
   BEGIN
   INSERT INTO JurnalTrans ( BDate, Hour, TransType, ExFile, IssueDate, KupaNum, StockID, Branch,DatF3, Ref2, Ref3, Quant, CostCode, UseFID, BatchNo, ValueDate, DueDate, 
   Description, Referance, Changable, suFDlr, suF, TransDebID, DebName, CredName,Status, CurrencyCode, TransCredID,DocumentID )
   SELECT Stock.KuDate, Stock.KUTime, Stock.TransType, Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.KupaNum, Stock.ID,Stock.BranchID, Stock.IssueDate, Stock.Reference /*Stock.DocNumber*/, stock.ref3, Stock.Quantity, 
   Stock.CostCode, Stock.UseFID AS Expr1, Stock.Batch, Stock.ValueDate,CreditPaysSplit.datf AS Expr2, Stock.Remarks, Stock.DocNumber, 0 AS Exp1,SUM(CreditPaysSplit.SuF) AS Expr3, SUM(CreditPaysSplit.SuFDlr),@Acct, 
   @AcctName, Accounts_1.FullName, 1 AS Expr6, 
   CreditPays.Currency AS Expr4, CreditPays.KupaKey,stock.DocumentID
   FROM (((Stock INNER JOIN CreditPays ON Stock.ID = CreditPays.DepositID) INNER JOIN CreditPaysSplit ON CreditPays.ID = CreditPaysSplit.CreditPayID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey) INNER JOIN Accounts AS Accounts_1 ON CreditPays.KupaKey = Accounts_1.AccountKey
   WHERE (((Stock.ID)=@MainStockId))
   GROUP BY Stock.KuDate, Stock.KUTime, STOCK.EXFILE,STOCK.KUPANUM, STOCK.ID, 
   STOCK.BRANCHID, STOCK.ISSUEDATE,STOCK.QUANTITY, 
   STOCK.COSTCODE, STOCK.USEFID, STOCK.BATCH, STOCK.VALUEDATE,
   STOCK.REMARKS, STOCK.DOCNUMBER,STOCK.ACCOUNTKEY, stock.ref3,
   ACCOUNTS.FULLNAME, ACCOUNTS_1.FULLNAME,CREDITPAYS.Currency,
   CREDITPAYSSPLIT.DATF, CREDITPAYS.KUPAKEY, CREDITPAYS.fdealtype, 
   STOCK.TRANSTYPE,stock.DocumentID,Stock.Reference
   SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 45, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END
 ELSE
   BEGIN
   select @LAST4DIG2REF = COMPANYDEFENITIONS.LAST4DIG2REF from COMPANYDEFENITIONS
   INSERT INTO JurnalTrans ( BDate, Hour, TransType, ExFile, IssueDate, KupaNum, StockID, Branch, DatF3, Ref2, Ref3, Quant, CostCode, UseFID, BatchNo, ValueDate, DueDate,Description, Referance, Changable, suFDLR, 
   TransDebID, DebName, CredName, Status, CurrencyCode, suF, TransCredID,DocumentID )
   SELECT Stock.KuDate, Stock.KUTime, Stock.TransType, Stock.ExFile, cast(convert(varchar(8),getdate(),1) as datetime)  AS Expr26, Stock.KupaNum, Stock.ID,Stock.BranchID, Stock.IssueDate, 
   CASE WHEN @LAST4DIG2REF = 1 THEN CreditPays.Last4dig ELSE Stock.Reference /*Stock.DocNumber*/ END, CASE WHEN @LAST4DIG2REF = 1 THEN Stock.Reference  WHEN STOCK.Ref3 > 0 THEN STOCK.Ref3 ELSE CreditPays.fShovar END, 
   Stock.Quantity, Stock.CostCode, Stock.UseFID AS Expr1, Stock.Batch, Stock.ValueDate,CreditPaysSplit.DatF AS Expr2, Stock.Remarks, Stock.DocNumber, 0 AS Exp1, 
   CreditPaysSplit.SuF AS Expr3, @Acct, @AcctName,Accounts_1.FullName, 1 AS Expr5, CreditPays.Currency, CreditPaysSplit.SuFDlr, 
   CreditPays.KupaKey,stock.DocumentID
   FROM (((Stock INNER JOIN CreditPays ON Stock.ID = CreditPays.DepositID) INNER JOIN CreditPaysSplit ON CreditPays.ID = CreditPaysSplit.CreditPayID) INNER JOIN Accounts ON Stock.AccountKey = Accounts.AccountKey) INNER JOIN Accounts AS Accounts_1 ON CreditPays.KupaKey = Accounts_1.AccountKey
   WHERE (((Stock.ID)=@MainStockId))
   SET @MYERROR = @@ERROR
   IF @MYERROR <> 0
    BEGIN
     RAISERROR ('PROCEDURE KB_Cancellation: 46, ERROR %d ', 19, 1,@MYERROR) WITH LOG
     RETURN @MYERROR  
    END
   END
  END

--תנועות יומן חובה לכותרות הנהח
--במידה ויש ניכוי במקור יעודכן בהמשך
IF @SourceTaxFlag = 0
BEGIN
INSERT INTO JurnalTransMoves ( TransID, AccountKey, DebitCredit, SuF, SuFDlr )
SELECT DISTINCT JurnalTrans.TransID, JurnalTrans.TransDebID, 1 AS Expr1, JurnalTrans.suF, JurnalTrans.suFDlr
FROM JurnalTrans
WHERE (((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 47, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--תנועות יומן זכות לכותרות הנהח
INSERT INTO JurnalTransMoves ( TransID, AccountKey, DebitCredit, SuF, SuFDlr )
SELECT DISTINCT JurnalTrans.TransID, JurnalTrans.TransCredID, 0 AS Expr1, JurnalTrans.suF, JurnalTrans.suFDlr
FROM JurnalTrans
WHERE (((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 48, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--שורה לניכוי במקור
INSERT INTO JurnalTransMoves ( TransID, AccountKey, DebitCredit, SuF, SuFDlr )
SELECT DISTINCT JurnalTrans.TransID, @KUPATNIKUI , 0 AS Expr1, 0 AS Expr2, 0 AS Expr3
FROM Stock INNER JOIN JurnalTrans ON Stock.ID = JurnalTrans.StockID
WHERE (((Stock.ID)=@MainStockId) AND ((Stock.TransType) IS NOT NULL) AND ((Stock.DocumentID)=41))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 49, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END
 --עדכון יתרת קופת אשראי
UPDATE  ACCOUNTS SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE + GRP.suf   FROM  ACCOUNTS inner join 
(select ACCOUNTS.AccountKey ,sum(jurnaltrans.suf) as suf FROM  ACCOUNTS, JurnalTrans  WHERE ((JurnalTrans.StockID)=@MainStockId)
AND ACCOUNTS.ACCOUNTKEY in (SELECT   KupaKey FROM dbo.CreditPays GROUP BY DepositID, KupaKey HAVING  DEPOSITID = @MainStockId)
group by ACCOUNTS.AccountKey,JurnalTrans.StockID  )as GRP  on Accounts.AccountKey = GRP.AccountKey 
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 50, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
--עדכון יתרת לקוח
UPDATE  ACCOUNTS SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE - GRP.suf   FROM  ACCOUNTS inner join 
(select ACCOUNTS.AccountKey , sum(jurnaltrans.suf) as suf FROM  ACCOUNTS, JurnalTrans  WHERE (((JurnalTrans.StockID)=@MainStockId) AND ((ACCOUNTS.ACCOUNTKEY)=@Acct))
group by ACCOUNTS.BALANCE,ACCOUNTS.AccountKey,JurnalTrans.StockID  )as GRP  on Accounts.AccountKey = GRP.AccountKey 
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 51, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
END  ---CREDIT



--חישוב ניכוי במקור מלקוחות
IF @SourceTaxFlag = 1
BEGIN
SELECT @SourceTax = CashPays.SourceTax ,@SourceTaxDlr=CashPays.TAXSUMDLR,@SourceTaxCur=CashPays.TaxCurrencyDlr,@SourceTaxDlrCur=CASHPAYS.CURRENCY	FROM CashPays WHERE StockID = @StockIdToCancel 
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 52, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

IF  @SourceTax is NULL 
BEGIN
    SET @SourceTax = 0
END
IF @SourceTax > 0
--רשומת כותרת הנהח לניכוי במקור שח
BEGIN
INSERT INTO JURNALTRANS ( EXFILE, ISSUEDATE, KUPANUM, STOCKID, DATF3, REF3, QUANT, COSTCODE, BRANCH, USEFID, BATCHNO, VALUEDATE, DUEDATE, DESCRIPTION, REF2, CURRENCYCODE, CHANGABLE, REFERANCE, SUF, TRANSCREDID, TRANSDEBID, 
CREDNAME, DEBNAME, SUFDLR, STATUS )
SELECT DISTINCT STOCK.EXFILE, cast(convert(varchar(8),getdate(),1) as datetime) as EXPR1, STOCK.KUPANUM, STOCK.ID, STOCK.ISSUEDATE, STOCK.REF3, STOCK.QUANTITY, STOCK.COSTCODE, 
STOCK.BRANCHID, STOCK.USEFID, STOCK.BATCH, STOCK.VALUEDATE, STOCK.VALUEDATE, STOCK.REMARKS,  STOCK.REFERENCE , 
@SourceTaxCur, 0 AS EXPR1,STOCK.DOCNUMBER, @SourceTax , COMPANYDEFENITIONS.DEDUCTACC , 
@Acct ,ACCOUNTS_1.FULLNAME ,  @AcctName, @SourceTaxDlr, 1 AS EXPR2
FROM ACCOUNTS, STOCK , COMPANYDEFENITIONS INNER JOIN ACCOUNTS AS ACCOUNTS_1 ON COMPANYDEFENITIONS.DEDUCTACC = ACCOUNTS_1.ACCOUNTKEY
WHERE (((STOCK.ID)=@MainStockId)  AND ((STOCK.CURRENCY)=@MAIN_CUR) AND ((ACCOUNTS.ACCOUNTKEY)=STOCK.ACCOUNTKEY))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 53, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--רשומת כותרת הנהח לניכוי במקור מטח
INSERT INTO JURNALTRANS ( EXFILE, ISSUEDATE, KUPANUM, STOCKID, DATF3, REF3, QUANT, COSTCODE, BRANCH, USEFID, BATCHNO, VALUEDATE, DUEDATE, DESCRIPTION, REF2, CURRENCYCODE, CHANGABLE, REFERANCE, SUF, TRANSCREDID, TRANSDEBID, 
CREDNAME, DEBNAME, SUFDLR, STATUS )
SELECT DISTINCT STOCK.EXFILE, cast(convert(varchar(8),getdate(),1) as datetime) as EXPR1, STOCK.KUPANUM, STOCK.ID, STOCK.ISSUEDATE, STOCK.REF3, STOCK.QUANTITY, STOCK.COSTCODE, STOCK.BRANCHID, STOCK.USEFID, STOCK.BATCH, 
STOCK.VALUEDATE, STOCK.VALUEDATE, STOCK.REMARKS, STOCK.REFERENCE, @SourceTaxDlrCur, 0 AS EXPR1,STOCK.DOCNUMBER , @SourceTaxDlr, COMPANYDEFENITIONS.DEDUCTACC , 
@Acct ,ACCOUNTS_1.FULLNAME ,  @AcctName, @SourceTax , 1 AS EXPR2
FROM ACCOUNTS, STOCK , COMPANYDEFENITIONS INNER JOIN ACCOUNTS AS ACCOUNTS_1 ON COMPANYDEFENITIONS.DEDUCTACC = ACCOUNTS_1.ACCOUNTKEY
WHERE (((STOCK.ID)=@MainStockId)  AND ((STOCK.CURRENCY)<>@MAIN_CUR) AND ((ACCOUNTS.ACCOUNTKEY)=STOCK.ACCOUNTKEY))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 54, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--תנועות יומן זכות לכותרות הנהח
INSERT INTO JURNALTRANSMOVES ( TRANSID, ACCOUNTKEY, DEBITCREDIT, SUF, SUFDLR )
SELECT DISTINCT JURNALTRANS.TRANSID, JURNALTRANS.TRANSCREDID, 0 AS EXPR1, JURNALTRANS.SUF, JURNALTRANS.SUFDLR
FROM STOCK INNER JOIN JURNALTRANS ON STOCK.ID = JURNALTRANS.STOCKID
WHERE (((STOCK.ID)=@MainStockId) )
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 55, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--תנועות יומן חובה לכותרות הנהח
INSERT INTO JURNALTRANSMOVES ( TRANSID, ACCOUNTKEY, DEBITCREDIT, SUF, SUFDLR )
SELECT DISTINCT JURNALTRANS.TRANSID, JURNALTRANS.TRANSDEBID, 1 AS EXPR1, JURNALTRANS.SUF, JURNALTRANS.SUFDLR
FROM STOCK INNER JOIN JURNALTRANS ON STOCK.ID = JURNALTRANS.STOCKID
WHERE (((STOCK.ID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 56, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

 --עדכון יתרת כרטיס ניכוי במקור
SET @BALANC=0
SELECT @BALANC=SUM(dbo.JurnalTransMoves.SuF) FROM dbo.JurnalTrans INNER JOIN dbo.JurnalTransMoves ON dbo.JurnalTrans.TransID = dbo.JurnalTransMoves.TransID
WHERE (((dbo.JurnalTrans.StockID)=@StockIdToCancel ) AND ((JurnalTransMoves.AccountKey)=@KUPATNIKUI) AND ((JurnalTransMoves.DebitCredit)=1))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 84, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

 UPDATE  ACCOUNTS SET ACCOUNTS.BALANCE = ACCOUNTS.BALANCE + @BALANC   FROM  ACCOUNTS Where AccountKey = @KUPATNIKUI  
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 85, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END


END
END

 --עדכון שדות תאריך ואסמכתא נוספים
UPDATE  JURNALTRANS 
SET JurnalTRans.ExtraNum1 = stock.ExtraNum1 ,JurnalTRans.ExtraNum2 = stock.ExtraNum2,
JurnalTRans.ExtraDate1 = stock.ExtraDate1 ,JurnalTRans.ExtraDate2 = stock.ExtraDate2 
FROM  JURNALTRANS INNER JOIN STOCK ON JURNALTRANS.STOCKID = STOCK.ID 
WHERE STOCK.ID= @StockIdToCancel
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 57, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

-- עדכון הערות נוספות
UPDATE JurnalTrans SET JurnalTrans.Details = Stock.ExtraText1 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=1) AND ((ExtraStockDef.ID)=1) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 58, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Details = Stock.ExtraText2 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=1) AND ((ExtraStockDef.ID)=2) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 59, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Details = Stock.ExtraText3 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=1) AND ((ExtraStockDef.ID)=3) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 60, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Details = Stock.ExtraText4 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=1) AND ((ExtraStockDef.ID)=4) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 61, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Details = Stock.ExtraText5 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=1) AND ((ExtraStockDef.ID)=5) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 62, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Det2 = Stock.ExtraText1 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=2) AND ((ExtraStockDef.ID)=1) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 63, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Det2 = Stock.ExtraText2 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=2) AND ((ExtraStockDef.ID)=2) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 64, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Det2 = Stock.ExtraText3 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=2) AND ((ExtraStockDef.ID)=3) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 65, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Det2 = Stock.ExtraText4 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=2) AND ((ExtraStockDef.ID)=4) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 66, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

UPDATE JurnalTrans SET JurnalTrans.Det2 = Stock.ExtraText5 FROM ExtraStockDef, JurnalTrans INNER JOIN Stock ON 
JurnalTrans.StockID = Stock.ID WHERE (((ExtraStockDef.UpJur)=2) AND ((ExtraStockDef.ID)=5) 
AND ((Stock.ID)=@MainStockId) AND ((JurnalTrans.StockID)=@MainStockId))
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 67, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--עדכון תאריך ושעה בכל פקודות היומן
UPDATE  JURNALTRANS 
SET JURNALTRANS.BDate = STOCK.kudate,
    JURNALTRANS.Hour = STOCK.kutime,
	JURNALTRANS.DocumentID = stock.DocumentID,
	JurnalTRans.ExtraNum1 = stock.ExtraNum1 ,JurnalTRans.ExtraNum2 = stock.ExtraNum2,
	JurnalTRans.ExtraDate1 = stock.ExtraDate1 ,JurnalTRans.ExtraDate2 = stock.ExtraDate2 
FROM  JURNALTRANS INNER JOIN STOCK ON JURNALTRANS.STOCKID = STOCK.ID 
WHERE STOCK.ID=@MainStockId
SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 68, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

--ביטול התאמות
IF @MATCHFLAG = 1
BEGIN
set @MatchToCancel = 0
    SELECT top 1 @MatchToCancel = matchnum FROM RECEIPTJURNALMATCH inner join JurnalTransMoves on RECEIPTJURNALMATCH.JurnalTransID = JurnalTransMoves.ID
    inner join JurnalTrans on JurnalTransMoves.TransID = JurnalTrans.TransID 
    WHERE JurnalTrans.StockID = @StockIdToCancel  and JurnalTransMoves.FullMatch = 1
	SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 69, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END


IF @MatchToCancel > 0 AND @MatchToCancel <> @MatchNum 
BEGIN
   Update JurnalTransMoves SET FullMatch=0 FROM  JurnalTransmoves Inner Join  ReceiptJurnalMatch 
   on JurnalTransmoves.id=ReceiptJurnalMatch.JurnalTransID
   WHERE ReceiptJurnalMatch.MatchNum= @MatchToCancel
   SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 70, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

   Delete FROM ReceiptJurnalMatch WHERE MatchNum = @MatchToCancel
   SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 71, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 END

END

--התאמת הקבלה לביטול
IF @MATCHFLAG = 1
BEGIN
---
--הגדרת משתנה לסוג ההתאמה שח או מטח
DECLARE @BlMSort INT
SET @BlMSort=0 --ברירת מחדל התאמת שח
--IF @STOCKCURR=0 
--   BEGIN
     SELECT @BlMSort =ACCOUNTS.MATCHCURRFLAG
     FROM ACCOUNTS
     WHERE (((ACCOUNTS.ACCOUNTKEY)=@Acct) AND ((ACCOUNTS.MATCHCURRFLAG)=1));

     SET @MYERROR = @@ERROR
     IF @MYERROR <> 0
      BEGIN
       RAISERROR ('PROCEDURE KB_Cancellation: 87, ERROR %d ', 19, 1,@MYERROR) WITH LOG
       RETURN @MYERROR  
      END

     IF @BlMSort=1 
       BEGIN
        SET @BlMSort=0
       END 
      ELSE
       BEGIN 
        SET @BlMSort=1
       END
--   END
---
INSERT INTO ReceiptJurnalMatch ( RSort, RDate, RTime, RUseFID, JurnalTransID, CurrencyCode, MatchNum, SuF)
SELECT DISTINCT  8, JURNALTRANS.BDate, JURNALTRANS.Hour, @USERID, JurnalTransMoves.ID,CASE WHEN @BlMSort = 0 THEN @MAIN_CUR ELSE jurnaltrans.CurrencyCode END, @MatchNum,
CASE WHEN @BlMSort = 0 THEN JurnalTransMoves.SuF ELSE jurnaltrans.suFDlr  END
FROM JurnalTrans inner join JurnalTransMoves on JurnalTrans.TransID = JurnalTransMoves.TransID 
   where JurnalTrans.StockID =@StockIdToCancel AND JurnalTrans.TransDebID = CASE WHEN @CashToCancel = 1 THEN @CashAccount WHEN @CheqsToCancel = 1 THEN (select top(1) transcredid from jurnaltrans where StockID = @MainStockId) 
   WHEN @CreditToCancel = 1 THEN (select top(1) transcredid from jurnaltrans where StockID = @MainStockId) END 
   AND JurnalTransMoves.AccountKey = @Acct 
  SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 79, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 --UPDATE JurnalTransMoves set FullMatch = 1 where ID = @JurnalMatchID
 UPDATE JurnalTransMoves set FullMatch = 1 FROM JurnalTrans inner join JurnalTransMoves on JurnalTrans.TransID = JurnalTransMoves.TransID 
   where JurnalTrans.StockID =@StockIdToCancel AND JurnalTrans.TransDebID = CASE WHEN @CashToCancel = 1 THEN @CashAccount WHEN @CheqsToCancel = 1 THEN (select top(1) transcredid from jurnaltrans where StockID = @MainStockId) 
   WHEN @CreditToCancel = 1 THEN (select top(1) transcredid from jurnaltrans where StockID = @MainStockId) END 
   AND JurnalTransMoves.AccountKey = @Acct 
  SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 80, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 --ניכוי במקור
 IF @SourceTaxFlag = 1
 BEGIN
 INSERT INTO ReceiptJurnalMatch ( RSort, RDate, RTime, RUseFID, JurnalTransID, CurrencyCode, MatchNum, SuF)
SELECT DISTINCT  8, JURNALTRANS.BDate, JURNALTRANS.Hour, @USERID, JurnalTransMoves.ID, CASE WHEN @BlMSort = 0 THEN @MAIN_CUR ELSE jurnaltrans.CurrencyCode END, @MatchNum, 
CASE WHEN @BlMSort = 0 THEN JurnalTransMoves.SuF ELSE jurnaltrans.suFDlr  END
FROM JurnalTrans inner join JurnalTransMoves on JurnalTrans.TransID = JurnalTransMoves.TransID 
   where JurnalTrans.StockID =@StockIdToCancel AND JurnalTrans.TransDebID = @KUPATNIKUI  AND JurnalTransMoves.AccountKey = @Acct 
  SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 79, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

 UPDATE JurnalTransMoves set FullMatch = 1 FROM JurnalTrans inner join JurnalTransMoves on JurnalTrans.TransID = JurnalTransMoves.TransID 
  where JurnalTrans.StockID =@StockIdToCancel AND JurnalTrans.TransDebID = @KUPATNIKUI  AND JurnalTransMoves.AccountKey = @Acct 
  SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 80, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END
 END
 --
INSERT INTO ReceiptJurnalMatch ( RSort, RDate, RTime, RUseFID, JurnalTransID, CurrencyCode, MatchNum, SuF)
SELECT DISTINCT  8, JURNALTRANS.BDate, JURNALTRANS.Hour, @USERID, JurnalTransMoves.ID, CASE WHEN @BlMSort = 0 THEN @MAIN_CUR ELSE jurnaltrans.CurrencyCode END, @MatchNum, 
CASE WHEN @BlMSort = 0 THEN JurnalTransMoves.SuF*-1 ELSE jurnaltrans.suFDlr *-1 END 
from JurnalTrans inner join JurnalTransMoves on JurnalTrans.TransID = JurnalTransMoves.TransID 
   where JurnalTrans.StockID =@MainStockId AND JurnalTransMoves.AccountKey = @Acct 
  SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 82, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

 --UPDATE JurnalTransMoves set FullMatch = 1 where ID = @JurnalMatchID
  UPDATE JurnalTransMoves set FullMatch = 1 from JurnalTrans inner join JurnalTransMoves on JurnalTrans.TransID = JurnalTransMoves.TransID 
   where JurnalTrans.StockID =@MainStockId AND JurnalTransMoves.AccountKey = @Acct 
  SET @MYERROR = @@ERROR
 IF @MYERROR <> 0
 BEGIN
   RAISERROR ('PROCEDURE KB_Cancellation: 83, ERROR %d ', 19, 1,@MYERROR) WITH LOG
   RETURN @MYERROR  
 END

END


COMMIT TRAN



RETURN 0


 
GO
