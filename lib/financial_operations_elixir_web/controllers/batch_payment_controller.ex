defmodule FinancialOperationsElixirWeb.BatchPaymentController do
  use FinancialOperationsElixirWeb, :controller

  alias FinancialOperationsElixir.Batches
  alias FinancialOperationsElixir.Batches.BatchPayment
  alias FinancialOperationsElixir.Payments
  alias FinancialOperationsElixir.Payments.Payment
  alias FinancialOperationsElixir.Transactions
  alias FinancialOperationsElixir.Transactions.Transaction
  alias FinancialOperationsElixirWeb.Services.Currencies.Exchange
  alias FinancialOperationsElixirWeb.Services.Utils.GenerateCode

  action_fallback FinancialOperationsElixirWeb.FallbackController

  def index(conn, _params) do
    batch_payments = Batches.list_batch_payments()
    render(conn, "index.json", batch_payments: batch_payments)
  end

  def create(conn, %{"batch_payment" => batch_payment_params}) do
    with {:ok, %BatchPayment{} = batch_payment} <- Batches.create_batch_payment(batch_payment_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.batch_payment_path(conn, :show, batch_payment))
      |> render("show.json", batch_payment: batch_payment)
    end
  end

  def show(conn, %{"id" => id}) do
    batch_payment = Batches.get_batch_payment!(id)
    render(conn, "show.json", batch_payment: batch_payment)
  end

  def update(conn, %{"id" => id, "batch_payment" => batch_payment_params}) do
    batch_payment = Batches.get_batch_payment!(id)

    with {:ok, %BatchPayment{} = batch_payment} <- Batches.update_batch_payment(batch_payment, batch_payment_params) do
      render(conn, "show.json", batch_payment: batch_payment)
    end
  end

  def delete(conn, %{"id" => id}) do
    batch_payment = Batches.get_batch_payment!(id)

    with {:ok, %BatchPayment{}} <- Batches.delete_batch_payment(batch_payment) do
      send_resp(conn, :no_content, "")
    end
  end

  ############### services ##############
  
  # currency service
  defp cambio(amount, currency_code) do
    currency_rate = Exchange.rate(currency_code)
    amount*currency_rate
  end
  
  # batches service
  # Create batch payment
  def create_batch_payment(conn, %{"total_value"=>total_value, "currency_id"=>currency_id, "payer_id"=>payer_id, "payments"=>payments}) do
    status = "open"
    batch_payment_params = %{"total_value"=>total_value, "currency_id"=>currency_id, "payer_id"=>payer_id, "payments"=>payments, "status"=>status}
    with {:ok, %BatchPayment{} = batch_payment} <- Batches.create_batch_payment(batch_payment_params) do
      mount_payments(payments)
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.batch_payment_path(conn, :show, batch_payment))
      |> render("show.json", batch_payment: batch_payment)
    end
  end

  # transactions service
  defp transactions_params(payment) do
    final_amount = cambio(payment.value, "USD") # get currebcy code from batch
    currency_id = 1 #get currency id from batch
    payer_id = 1 #get payer id from batch
    account_id = 1 # get account id trougth beneficiary
    payer_value_date = ~D[2010-04-17] # get date from batch(add to batch)
    %{"tracking_code"=>payment.tracking_code, "amount"=>payment.value, "final_amount"=>final_amount, "payer_value_date"=>payer_value_date, "currency_id"=>currency_id, "account_id"=>account_id, "payer_id"=>payer_id}
  end

  def create_transaction(payment) do
    with {:ok, %FinancialOperationsElixir.Transactions.Transaction{} = transaction} <- transactions_params(payment) |> Transactions.create_transaction() do
      IO.inspect transaction
    end 
  end

  # payments service
  #Payment struct
  defmodule Payment do
    defstruct tracking_code: "", value: 0.0, beneficiary_id: 0, transaction_id: 0, batch_id: 0 
  end

  defp payments(payments_drafts_json) do
    Poison.decode!(payments_drafts_json, as: [%Payment{}])
  end

  defp payments_params(payment_draft) do
    %{"tracking_code"=>payment_draft.tracking_code, "value"=>payment_draft.value, "transaction_id"=>payment_draft.transaction_id, "beneficiary_id"=>payment_draft.beneficiary_id, "batch_id"=>payment_draft.batch_id}
  end

  defp create_payment(payment_draft) do
    tracking_code = GenerateCode.generate(10)
    batch_id = System.unique_integer()
    transaction_id = System.unique_integer()
    beneficiary_id = System.unique_integer()
    payment_draft = %{payment_draft | transaction_id: transaction_id, batch_id: batch_id, tracking_code: tracking_code, beneficiary_id: beneficiary_id}
    
    with {:ok, %FinancialOperationsElixir.Payments.Payment{} = payment} <- payments_params(payment_draft) |> Payments.create_payment() do
      create_transaction(payment)
    end 
  end 

  defp mount_payments(payments_drafts_json) do
    Enum.each(payments(payments_drafts_json), &create_payment/1)  
  end
end
