CREATE PROCEDURE Generate_Perceive_Finalise_Invoice  
@billStartdate DATETIME,  
@billEndDate  DATETIME,  
@provinceId INT = 0,  
@paymentId INT= 0,  
@countryId INT = 0  
AS   
-- EXEC Generate_Perceive_Finalise_Invoice '2017-08-01', '2017-09-30',0,0,0  
BEGIN  
 SELECT    
 CAST(RIGHT('000000' + CONVERT(VARCHAR(6),RIGHT(ROW_NUMBER() OVER (ORDER BY A.fd_id), 6)) ,6) AS VARCHAR) AS fd_billing_txn_id  
 ,C.fd_id AS fd_customer_id,
 A.fd_id AS fd_agreement_id,
 A.fd_no AS fd_agreement_no, 
 A.fd_next_debit_date AS fd_bill_date  
,fd_bill_amount =CAST((CASE WHEN isNULL(CSA.fd_service_country,C.fd_mailing_country) = 1 THEN  
      (isNULL(( SELECT SUM(sAPD.fd_price)   
        FROM   tbl_Agreement sA(NOLOCK)  
        INNER JOIN tbl_Agreement_Product_Details sAPD (NOLOCK)ON sAPD.fd_agreement_id = sA.fd_id  
        WHERE sAPD.fd_free = 'N' --AND sAPD.fd_type = 'L'  
        AND sA.fd_id = A.fd_id  
        GROUP BY sA.fd_id  
       ),0)  
       +  
       -- PaperBilling Amount  
     isNULL((SELECT TOP 1 CASE PM.fd_green_billing WHEN 'Y' THEN 0 ELSE MAX(Prg.fd_paper_billing) END   
       FROM   tbl_Agreement sA(NOLOCK)  
       INNER JOIN tbl_Agreement_Product_Details sAPD (NOLOCK)ON sAPD.fd_agreement_id = sA.fd_id  
       INNER JOIN tbl_Payment_Mode PM (NOLOCK) ON PM.fd_id = sA.fd_payment_mode  
       INNER JOIN tbl_Program Prg(NOLOCK) ON Prg.fd_id = sAPD.fd_program_id  
       WHERE sAPD.fd_free = 'N' --AND sAPD.fd_type = 'L'  
       AND sA.fd_id = A.fd_id  
       GROUP BY sA.fd_id,Prg.fd_paper_billing,PM.fd_green_billing  
      ),0)  
      )  
     ELSE  
     ( isNULL((SELECT SUM(sAPD.fd_price * CASE P.fd_measurement WHEN 'Q' THEN (ISnull(sAPD.fd_qty,1) - ISnull(P.fd_qty,1)) ELSE ISnull(sAPD.fd_qty,1) END)   
        FROM   tbl_Agreement sA(NOLOCK)  
        INNER JOIN tbl_Agreement_Product_Details sAPD (NOLOCK)ON sAPD.fd_agreement_id = sA.fd_id  
        INNER JOIN tbl_Product P  (NOLOCK)ON sAPD.fd_product_id = P.fd_id  
        WHERE sAPD.fd_free = 'N' AND sAPD.fd_type = 'L'  
        AND sA.fd_id = A.fd_id  
        GROUP BY sA.fd_id  
       ),0)   
       +  
       -- PaperBilling Amount  
      isNULL((SELECT TOP 1 CASE PM.fd_green_billing WHEN 'Y' THEN 0 ELSE MAX(Prg.fd_paper_billing) END   
       FROM   tbl_Agreement sA(NOLOCK)  
       INNER JOIN tbl_Agreement_Product_Details sAPD (NOLOCK)ON sAPD.fd_agreement_id = sA.fd_id  
       INNER JOIN tbl_Payment_Mode PM (NOLOCK) ON PM.fd_id = sA.fd_payment_mode  
       INNER JOIN tbl_Program Prg(NOLOCK) ON Prg.fd_id = sAPD.fd_program_id  
       WHERE sAPD.fd_free = 'N' --AND sAPD.fd_type = 'L'  
       AND sA.fd_id = A.fd_id  
       GROUP BY sA.fd_id,Prg.fd_paper_billing,PM.fd_green_billing  
      ),0)  
     )    
   END)AS DECIMAL(10,2))  
   
 ,CAST(A.fd_tax AS DECIMAL(10,2)) AS fd_tax  
 ,CAST(0 AS DECIMAL(10,2)) AS fd_total_amount  
 ,A.fd_next_bill_start_date  
   
 ,DATEADD(DAY,-1,DATEADD(MONTH,1,ISNULL(A.fd_next_bill_start_date,A.fd_bill_start_date))) AS fd_next_bill_end_date   
 ,A.fd_next_debit_date  
 ,A.fd_next_prefered_debit_date  
 ,A.fd_payment_mode  
 ,As_billing_type = (SELECT TOP 1 ISNULL(Prg.fd_billing_method,1) FROM   tbl_Agreement sA(NOLOCK)  
      INNER JOIN tbl_Agreement_Product_Details sAPD (NOLOCK)ON sAPD.fd_agreement_id = sA.fd_id  
      INNER JOIN tbl_Program Prg(NOLOCK) ON Prg.fd_id = sAPD.fd_program_id  
      WHERE sA.fd_id = A.fd_id  
     )  
 ,A.fd_previous_balance  ,ISNULL(C.fd_service_country, C.fd_mailing_country) AS fd_country_id,  
 ISNULL(C.fd_service_province, C.fd_mailing_province) AS fd_province_id  
 INTO #tmp_BTS  
 FROM tbl_Agreement(NOLOCK) A  
 INNER JOIN tbl_Customer(NOLOCK) C ON C.fd_id = A.fd_customer_id  
 LEFT JOIN tbl_Customer_Service_Address CSA (NOLOCK) ON CSA.fd_id = A.fd_customer_service_address_id  
 WHERE A.fd_status = 'INCompleted'  
 AND A.fd_service_start_date IS NOT NULL  
 AND A.fd_next_bill_start_date IS NOT NULL  
 AND A.fd_next_debit_date IS NOT NULL  
 AND ( ( (CAST(A.fd_next_debit_date AS DATE) BETWEEN CAST(@billStartdate AS DATE)  AND CAST(@billEndDate AS DATE))  
    AND A.fd_next_prefered_debit_date IS NULL   
   )  
  OR  ( A.fd_next_prefered_debit_date IS NOT NULL  
    AND CAST(A.fd_next_prefered_debit_date AS DATE)BETWEEN CAST(@billStartdate AS DATE)  AND CAST(@billEndDate AS DATE)   
   )  
  )  
 AND (@paymentId = 0 OR (@paymentId > 0 AND A.fd_payment_mode = @paymentId))  
   
   
 UPDATE #tmp_BTS  
 SET fd_billing_txn_id = CAST('MNL' AS VARCHAR) + CONVERT(VARCHAR(10),GETDATE(),112) + CAST(REPLACE(CONVERT(VARCHAR(10),GETDATE(),108),':','') AS VARCHAR) + CAST(fd_billing_txn_id  AS VARCHAR)  
 --,fd_tax = fd_bill_amount * (fd_tax / 100)  
 --,fd_total_amount = fd_bill_amount + (fd_bill_amount * (fd_tax / 100))  
 ,fd_next_bill_end_date =   
  CASE WHEN As_billing_type = 1   
     AND fd_next_prefered_debit_date IS NOT NULL   
     AND CAST(fd_next_prefered_debit_date AS DATE) > CAST(fd_next_bill_start_date AS DATE)   
    THEN DATEADD(DAY,-1,fd_next_prefered_debit_date)  
    WHEN As_billing_type = 2   
     AND fd_next_prefered_debit_date IS NOT NULL   
     AND CAST(fd_next_prefered_debit_date AS DATE) > CAST(fd_next_bill_start_date AS DATE)   
    THEN DATEADD(DAY,-1,DATEADD(MONTH,1,fd_next_prefered_debit_date))   
    ELSE fd_next_bill_end_date END   
   
 --Billing Method 1:Arr 2: Adv  
 UPDATE #tmp_BTS  
 SET fd_bill_amount = dbo.fun_Calculate_Partial_Billing(fd_bill_amount,fd_next_bill_start_date,fd_next_bill_end_date)  
 WHERE fd_next_prefered_debit_date IS NOT NULL  
 AND CAST(fd_next_prefered_debit_date AS DATE) > CAST(fd_next_bill_start_date AS DATE)   
   
 UPDATE #tmp_BTS  
 SET fd_tax = fd_bill_amount * (fd_tax / 100)  
 ,fd_total_amount = fd_bill_amount + (fd_bill_amount * (fd_tax / 100))  
   
 --Billing Type 1:Debit 2:Credit   
 CREATE TABLE #tBilling_Transactions_Detail(fd_customer_id INT ,fd_agreement_id INT NULL,fd_transaction_id TINYINT NULL,fd_transaction_code VARCHAR(10),fd_billing_txn_id VARCHAR(30)  
 ,fd_billing_type TINYINT,fd_bill_date DATETIME,fd_billed_amount DECIMAL(10,2),fd_tax_amount DECIMAL(10,2),fd_total_amount DECIMAL(10,2)  
 ,fd_billing_period_from_date DATETIME,fd_billing_period_to_date DATETIME,fd_payment_mode_id TINYINT,fd_comments VARCHAR(300) NULL,  
 fd_status CHAR(1) NULL, fd_created_on DATETIME)  
   
   
 INSERT INTO #tBilling_Transactions_Detail(fd_customer_id  ,fd_agreement_id ,fd_transaction_id ,fd_transaction_code ,fd_billing_txn_id ,  
  fd_billing_type  ,fd_bill_date ,fd_billed_amount ,fd_tax_amount ,fd_total_amount  
 ,fd_billing_period_from_date ,fd_billing_period_to_date ,fd_payment_mode_id ,fd_comments ,  
 fd_status , fd_created_on )  
 SELECT fd_customer_id,fd_agreement_id,1,'CHRG',fd_billing_txn_id,1,fd_bill_date,fd_bill_amount,fd_tax,fd_total_amount  
 ,fd_next_bill_start_date,fd_next_bill_end_date,fd_payment_mode,'Agreement Charge',NULL,GETDATE()  
 FROM #tmp_BTS  
 WHERE (@countryId = 0 OR(@countryId > 0 AND fd_country_id = @countryId))  
 --AND (@provinceId = 0 OR(@provinceId > 0 AND fd_country_id = @provinceId))  
  
    --Adjustment Billing--  
  SELECT AdjI.fd_id,CAST(RIGHT('000000' + CONVERT(VARCHAR(6),RIGHT(ROW_NUMBER() OVER (ORDER BY AdjI.fd_id), 6)) ,6) AS VARCHAR) AS fd_billing_txn_id  
  ,Adj.fd_customer_id,Adj.fd_agreement_id,AdjI.fd_amount AS fd_bill_amount,AdjI.fd_tax_value AS fd_tax,AdjI.fd_total_amount  
  ,AdjI.fd_effective_date AS fd_next_bill_start_date,AdjI.fd_effective_date AS fd_next_bill_end_date,Adj.fd_payment_menthod AS fd_payment_mode  
  ,AdjR.fd_name AS fd_comments  
  ,fd_bill_date  
  ,Adj.fd_type AS fd_billing_type  
  INTO #tmp_BTS_Adjustment  
  FROM tbl_Adjustment_Installments(NOLOCK) AdjI  
  INNER JOIN tbl_Adjustments(NOLOCK) Adj ON Adj.fd_id = AdjI.fd_adjustment_id  
  INNER JOIN tbl_Adjustment_Reason(NOLOCK) AdjR ON AdjR.fd_id = Adj.fd_reason  
  INNER JOIN #tmp_BTS tBTS ON tBTS.fd_agreement_id = Adj.fd_agreement_id  
  WHERE AdjI.fd_billing_status IS NULL  
  AND AdjI.fd_status = 'A'  
  AND Adj.fd_status = 6  
  AND Adj.fd_issue_invoice = 'N'  
  AND CAST(AdjI.fd_effective_date AS DATE) BETWEEN CAST(tBTS.fd_next_bill_start_date AS DATE) AND CAST(tBTS.fd_next_bill_end_date AS DATE)  
  AND ( @countryId = 0 OR( @countryId > 0 AND tBTS.fd_country_id = @countryId))  
    
 UPDATE #tmp_BTS_Adjustment  
 SET fd_billing_txn_id = CAST('ADJ' AS VARCHAR) + CONVERT(VARCHAR(10),GETDATE(),112) + CAST(REPLACE(CONVERT(VARCHAR(10),GETDATE(),108),':','') AS VARCHAR) + CAST(fd_billing_txn_id  AS VARCHAR)  
   
 INSERT INTO #tBilling_Transactions_Detail(fd_customer_id  ,fd_agreement_id ,fd_transaction_id ,fd_transaction_code ,fd_billing_txn_id ,  
  fd_billing_type  ,fd_bill_date ,fd_billed_amount ,fd_tax_amount ,fd_total_amount  
 ,fd_billing_period_from_date ,fd_billing_period_to_date ,fd_payment_mode_id ,fd_comments ,  
 fd_status , fd_created_on )  
 SELECT fd_customer_id,fd_agreement_id,2,'ADJ',fd_billing_txn_id,fd_billing_type,fd_bill_date,fd_bill_amount,fd_tax,fd_total_amount  
 ,fd_next_bill_start_date,fd_next_bill_end_date,fd_payment_mode,fd_comments,NULL,GETDATE()  
 FROM #tmp_BTS_Adjustment  
   
   
 SELECT CAST(RIGHT('000000' + CONVERT(VARCHAR(6),RIGHT(ROW_NUMBER() OVER (ORDER BY fd_agreement_id), 6)) ,6) AS VARCHAR) AS fd_invoice_txn_id  
 ,fd_customer_id,fd_agreement_id,fd_bill_date,fd_payment_mode_id  
 ,SUM(fd_billed_amount) AS fd_billed_amount,SUM(fd_tax_amount) AS fd_tax_amount,SUM(fd_total_amount) AS fd_total_amount   
 ,CAST(0 AS NUMERIC(10,2)) AS fd_previous_balance,CAST(0 AS NUMERIC(10,2)) AS fd_payments,CAST(0 AS NUMERIC(10,2)) AS fd_adjustments  
 INTO #tmp_INV  
 FROM #tBilling_Transactions_Detail   
 GROUP BY fd_customer_id,fd_agreement_id,fd_bill_date,fd_payment_mode_id   
   
 SELECT fd_customer_id,fd_agreement_id,fd_bill_date,fd_payment_mode_id  
 ,SUM(fd_billed_amount) AS fd_billed_amount,SUM(fd_tax_amount) AS fd_tax_amount,SUM(fd_total_amount) AS fd_total_amount   
 INTO #tmp_INV_CHRG  
 FROM #tBilling_Transactions_Detail   
 WHERE fd_transaction_id = 1  
 GROUP BY fd_customer_id,fd_agreement_id,fd_bill_date,fd_payment_mode_id  
  
  
 SELECT fd_customer_id,fd_agreement_id,fd_bill_date,fd_payment_mode_id  
 ,SUM(fd_billed_amount) AS fd_billed_amount,SUM(fd_tax_amount) AS fd_tax_amount,SUM(fd_total_amount) AS fd_total_amount   
 INTO #tmp_INV_Adj  
 FROM #tBilling_Transactions_Detail   
 WHERE fd_transaction_id = 2  
 GROUP BY fd_customer_id,fd_agreement_id,fd_bill_date,fd_payment_mode_id  
   
 UPDATE #tmp_INV  
 SET fd_invoice_txn_id = CAST('INV' AS VARCHAR) + CONVERT(VARCHAR(10),GETDATE(),112) + CAST(REPLACE(CONVERT(VARCHAR(10),GETDATE(),108),':','') AS VARCHAR) + CAST(fd_invoice_txn_id  AS VARCHAR)   
   
 UPDATE tI  
 SET fd_total_amount = tC.fd_total_amount  
 ,fd_billed_amount = tC.fd_billed_amount  
 ,fd_tax_amount = tC.fd_tax_amount  
 FROM #tmp_INV tI  
 INNER JOIN #tmp_INV_CHRG tC ON tC.fd_customer_id = tI.fd_customer_id  
 AND tC.fd_agreement_id = tI.fd_agreement_id  
 AND tC.fd_payment_mode_id = tI.fd_payment_mode_id  
 AND tC.fd_bill_date = tI.fd_bill_date  
 AND tC.fd_bill_date = tI.fd_bill_date  
   
 UPDATE tI  
 SET fd_adjustments = tA.fd_total_amount  
 FROM #tmp_INV tI  
 INNER JOIN #tmp_INV_Adj tA ON tA.fd_customer_id = tI.fd_customer_id  
 AND tA.fd_agreement_id = tI.fd_agreement_id  
 AND tA.fd_payment_mode_id = tI.fd_payment_mode_id  
 AND tA.fd_bill_date = tI.fd_bill_date  
   
 SELECT PTD.fd_customer_id,PTD.fd_agreement_id,SUM(ABS(fd_amount)) AS fd_amount  
 INTO #tmp_PYMNT  
 FROM tbl_Payment_Transactions_Detail(NOLOCK) PTD  
 INNER JOIN #tBilling_Transactions_Detail tB ON PTD.fd_customer_id = tB.fd_customer_id  
 AND PTD.fd_agreement_id = tB.fd_agreement_id   
 WHERE CAST(PTD.fd_posted_date AS DATE) BETWEEN CAST(tB.fd_billing_period_from_date AS DATE) AND CAST(tB.fd_billing_period_to_date AS DATE)  
 AND PTD.fd_status = 'A'  
 GROUP BY PTD.fd_customer_id,PTD.fd_agreement_id  
   
 --Update Payments  
 UPDATE tI  
 SET fd_payments = tp.fd_amount  
 FROM #tmp_INV tI  
 INNER JOIN #tmp_PYMNT tP ON tP.fd_customer_id = tI.fd_customer_id  
 AND tP.fd_agreement_id = tI.fd_agreement_id  
   
   
 SELECT  tI.fd_customer_id,C.fd_code AS fd_customer_code,tI.fd_invoice_txn_id AS fd_invoice_number  
 ,ISNULL(A.fd_previous_balance,0) AS fd_previous_balance,tI.fd_billed_amount AS fd_invoice_amount,tI.fd_tax_amount,tI.fd_adjustments  
 ,tI.fd_payments,((ISNULL(A.fd_previous_balance,0) + tI.fd_adjustments + tI.fd_total_amount)-(tI.fd_payments)) AS fd_total_amount  
 ,C.fd_first_name,C.fd_last_name,fd_payment_mode_id,  
 P.fd_name,ISNULL(A.fd_no,'') AS fd_agreement_no,CONVERT( VARCHAR(10),tI.fd_bill_date,101 ) AS fd_invoice_date,  
 CONVERT( VARCHAR(10),tI.fd_bill_date,101 ) AS fd_bill_start_date,ISNULL(C.fd_mailing_province,C.fd_service_province) AS fd_province_id,  
 ISNULL(C.fd_mailing_country,C.fd_service_country) AS fd_country_id,A.fd_id AS fd_agreement_id  
 INTO #temp_Perceive  
 FROM #tmp_INV tI  
 INNER JOIN tbl_Customer C ON C.fd_id = tI.fd_customer_id  
 INNER JOIN tbl_Payment_Mode P ON P.fd_id = tI.fd_payment_mode_id  
 INNER JOIN tbl_Agreement A On A.fd_customer_id = C.fd_id AND A.fd_id = tI.fd_agreement_id  
 WHERE (@paymentId = 0 OR (@paymentId > 0 AND tI.fd_payment_mode_id = @paymentId))  
   
   
 SELECT fd_customer_id, fd_customer_code, fd_invoice_number  
 , fd_previous_balance, fd_invoice_amount,fd_tax_amount,fd_adjustments  
 ,t.fd_payments, fd_total_amount  
 ,fd_first_name,fd_last_name,fd_payment_mode_id,  
 t.fd_name, fd_agreement_no, fd_invoice_date,  
 fd_bill_start_date, fd_province_id,  
 t.fd_country_id, fd_agreement_id ,P.fd_name AS fd_province_name  
 FROM #temp_Perceive t  
 INNER JOIN tbl_Province  P ON t.fd_province_id = P.fd_id  
 WHERE ((@provinceId )= 0 OR (@provinceId > 0 AND t.fd_province_id = @provinceId))  
 AND ((@countryId = 0 )OR(@countryId > 0 AND t.fd_country_id = @countryId))  
 ORDER BY t.fd_invoice_date DESC  
   
 SELECT  SUM(fd_total_amount) AS fd_total_amount,tP.fd_country_id,fd_province_id  
 ,fd_payment_mode_id  
 ,P.fd_name AS fd_province_name,tP.fd_name  
 ,fd_invoice_date,fd_bill_start_date , cast( 0 as decimal)AS fd_credit_amount, cast( 0 as decimal) AS fd_debit_amount  
 FROM #temp_Perceive tP  
 INNER JOIN tbl_Province P ON P.fd_id = tp.fd_province_id   
 WHERE ((@provinceId = 0) OR (@provinceId > 0 AND tP.fd_province_id = @provinceId))  
 AND ((@countryId = 0) OR(@countryId > 0 AND tP.fd_country_id = @countryId))  
 GROUP BY fd_bill_start_date,fd_invoice_date,tP.fd_country_id,fd_province_id,P.fd_name,tP.fd_name,fd_payment_mode_id  
   
END   
  
  
