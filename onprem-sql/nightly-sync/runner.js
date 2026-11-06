const sql = require('mssql');

const memberId = Number(process.env.MEMBER_ID || 1001);
const config = {
  server: process.env.SQL_SERVER || 'sqlserver',
  database: process.env.SQL_DATABASE || 'CaldovaBenefits',
  user: process.env.SQL_USER,
  password: process.env.SQL_PASSWORD,
  options: {
    appName: process.env.SQL_APPLICATION_NAME || 'caldova-nightly-benefits-sync',
    encrypt: true,
    trustServerCertificate: true
  },
  pool: {
    min: 0,
    max: 1
  }
};

if (!config.user || !config.password) {
  throw new Error('SQL_USER and SQL_PASSWORD are required.');
}

async function run() {
  const pool = await sql.connect(config);
  const transaction = new sql.Transaction(pool);
  await transaction.begin(sql.ISOLATION_LEVEL.READ_COMMITTED);

  try {
    await new sql.Request(transaction)
      .input('memberId', sql.Int, memberId)
      .query(`
        UPDATE dbo.MemberBenefits
        SET LastVerifiedAt = SYSUTCDATETIME()
        WHERE MemberId = @memberId;

        WAITFOR DELAY '23:59:59';
      `);
    await transaction.commit();
  } catch (error) {
    console.log(`Nightly benefits sync stopped: ${error.message}`);
    await pool.close();
  }
}

run().catch(error => {
  console.error(`Nightly benefits sync failed: ${error.message}`);
  process.exitCode = 1;
});
